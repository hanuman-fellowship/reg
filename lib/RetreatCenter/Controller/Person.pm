use strict;
use warnings;
package RetreatCenter::Controller::Person;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    affil_table
    trim
    empty
    nsquish
    valid_email
    model
    tt_today
    commify
    dcm_registration
    payment_warning
    normalize
    stash
    error
    invalid_amount
/;
use Date::Simple qw/
    date
    today
/;
use Time::Simple qw/
    get_time    
/;
use Global qw/
    %string
/;
use USState;
use LWP::Simple;
use Template;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('search');
}

sub _view_person {
    my ($p) = @_;
    "<a href='/person/view/" . $p->id . "'>"
    . $p->first . " " . $p->last
    . "</a>";
}

sub search : Local {
    my ($self, $c, $pattern, $field, $nrecs) = @_;

    if ($pattern) {
        $c->stash->{message}  = "No one found matching '$pattern'.";
    }
    $c->stash->{pattern} = $pattern;
    if (! $field) {
        $c->stash->{last_selected} = "selected";
    }
    for my $f (qw/ 
        last sanskrit zip_post email first tel_home prefix substr
    /) {
        if (defined $field && $field eq $f) {
            $c->stash->{"$f\_selected"} = "selected";
        }
    }
    my @files = <root/static/mlist/* root/static/temple/*>;
    stash($c,
        pg_title => "People Search",
        online   => scalar(@files),
        template => "person/search.tt2",
    );
}

sub search_do : Local {
    my ($self, $c) = @_;

    my $pattern = trim($c->request->params->{pattern});
    my $orig_pattern = $pattern;
    $pattern =~ s{\*}{%}g;
    # % in a web form messes with url encoding... :(
    # even when method=post?

    my $field   = $c->request->params->{field};
    my $nrecs = 15;
    if ($pattern =~ s{\s+(\d+)\s*$}{}) {
        $nrecs = $1;
    }
    my $offset  = $c->request->params->{offset} || 0;
    my $search_ref;
    if ($pattern =~ m{\s+} && ($field eq 'last' || $field eq 'first')) {
        my ($A, $B) = split /\s+/, $pattern, 2;
        if ($field eq 'last') {
            $search_ref = {
                last =>  { 'like', "$A%" },
                first => { 'like', "$B%" },
            };
        }
        else {
            $search_ref = {
                last =>  { 'like', "$B%" },
                first => { 'like', "$A%" },
            };
        }
    }
    elsif ($field eq 'tel_home' && !($pattern =~ s{^(['"])(.*)\1}{$2})) {
        # intersperse % in the pattern - unless it was quoted
        $pattern =~ s{(\d)}{$1%}g;
        $search_ref = {
            tel_home => { like => "%$pattern" },
        };
    }
    else {
        $search_ref = {
            $field => { 'like', "$pattern%" },
        };
    }

    my %order_by = (
        sanskrit => [ 'sanskrit', 'last', 'first' ],
        zip_post => [ 'zip_post', 'last', 'first' ],
        last     => [ 'last', 'first' ],
        first    => [ 'first', 'last' ],
        email    => [ 'email', 'last', 'first' ],
        tel_home => [ 'last', 'first' ],
    );
    my @people = model($c, 'Person')->search(
        $search_ref,
        {
            order_by => $order_by{$field},
            rows     => $nrecs+1,       # +1 so we know if there are more
                                        # to be seen.  the extra one is
                                        # popped off below.
            offset   => $offset,
        },
    );
    if (@people == 0) {
        # Nobody found.
        $c->response->redirect($c->uri_for("/person/search/$orig_pattern/$field/$nrecs"));
        return;
    }
    if (@people == 1) {
        # just one so show their Person recrod
        view($self, $c, $people[0]);
        return;
    }
    if ($offset) {
        $c->stash->{N} = $nrecs;
        $c->stash->{prevN} = $c->uri_for('/person/search_do')
                            . "?" 
                            . "pattern=$orig_pattern"
                            . "&field=$field"
                            . "&nrecs=$nrecs"
                            . "&offset=" . ($offset-$nrecs);
    }
    if (@people > $nrecs) {
        pop @people;
        $c->stash->{N} = $nrecs;
        $c->stash->{nextN} = $c->uri_for('/person/search_do')
                            . "?" 
                            . "pattern=$orig_pattern"
                            . "&field=$field"
                            . "&nrecs=$nrecs"
                            . "&offset=" . ($offset+$nrecs);
    }
    $c->stash->{field} = $field eq 'tel_home'? 'tel_home': 'email';
    $c->stash->{ids} = join '-', map { $_->id } @people;
    $c->stash->{people} = \@people;
    $c->stash->{field_desc} = $field eq 'tel_home'? 'Home Phone'
                              :                     ucfirst $field;
    $c->stash->{pattern} = $orig_pattern;
    $c->stash->{template} = "person/search_result.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Person')->find($id);

    #
    # if this person is a leader or a member (or has made donations)
    # they can't be deleted.  their leadership
    # and membership must be deleted first.
    # I could ask if they would like me to do
    # that for them but I don't feel like it at the moment.
    # it _should_ be hard to delete such people.
    #
    # what about registrations???  these, too.
    #
    if ($p->leader || $p->member) {
        # ??? does this do repeated searches?  ask once, sent the
        # answer to the template.
        $c->stash->{person} = $p;
        $c->stash->{conjunction} = " and a " if $p->leader && $p->member;
        $c->stash->{template} = "person/memberleader.tt2";
        return;
    }
    if (my @r = $p->registrations) {
        $c->stash->{person} = $p;
        $c->stash->{registrations} = \@r;
        $c->stash->{template} = "person/nodel_reg.tt2";
        return;
    }
    if (my @d = $p->donations) {
        $c->stash->{person} = $p;
        $c->stash->{donations} = \@d;
        $c->stash->{template} = "person/nodel_don.tt2";
        return;
    }
    if (my @p = $p->payments) {
        $c->stash->{person} = $p;
        $c->stash->{payments} = \@p;
        $c->stash->{template} = "person/nodel_pay.tt2";
        return;
    }
    if (my @r = $p->rides) {
        $c->stash->{person} = $p;
        $c->stash->{rides} = \@r;
        $c->stash->{template} = "person/nodel_ride.tt2";
        return;
    }

    # affilation/persons
    model($c, 'AffilPerson')->search(
        { p_id => $id }
    )->delete();

    # unpartner the partner as their spouse is dying
    # will they remarry?
    if ($p->partner) {
        $p->partner->update({
            id_sps => 0,
        });
    }
    #
    # don't do $p->delete() as it does a dangerous cascade.
    # for one, it deletes the partner record rather than updating it as above.
    # ??? some other way aside from reSearching?
    #
    my $name = $p->first() . " " . $p->last();
    model($c, 'Person')->search(
        { id => $id }
    )->delete();

    $c->flash->{message} = "$name was deleted.";
    $c->response->redirect($c->uri_for('/person/search'));
}

sub _what_gender {
    my ($name, $id) = @_;

    my $html = get("http://www.gpeters.com/names/baby-names.php?"
                  ."name=" . $name);
    my ($likelihood, $gender) =
        $html =~ m{popular usage, it is <b>([\d.]+).*?to be a (\w+)'s};
    my %name = qw(
        girl Female
        boy  Male
    );
    if ($gender) {
        my $sex = $name{$gender};
        if ($id) {
            return "$likelihood => <a href='/person/set_gender/$id/"
                 . substr($sex, 0, 1)
                 . "'>$sex";
        }
        else {
            return "$likelihood => $sex";
        }
    }
    if (($gender) = $html =~ m{It's a (.*?)!}) {
        my $sex = $name{$gender};
        return "<a href='/person/set_gender/$id/"
                 . substr($sex, 0, 1)
                 . "'>$sex";
    }
    return "Only God knows.";
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $p;
    if (ref($id)) {
        # called with Person object
        $p = $id;
    }
    else {
        # called with numeric id
        $p = model($c, 'Person')->find($id);
    }
    if (! $p) {
        $c->stash->{mess} = "Person not found - sorry.";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }
    my $sex = $p->sex();
    stash($c,
        person   => $p,
        pg_title => $p->first() . ' ' . $p->last(),
        sex      => (!defined $sex || !$sex)? "Not Reported"
                          :($sex eq "M"           )? "Male"
                          :($sex eq "F"           )? "Female"
                          :                          "Not Reported",
        template => "person/view.tt2",
    );
}

sub create : Local {
    my ($self, $c) = @_;

    stash($c,
        e_mailings         => "checked",
        snail_mailings     => "checked",
        mmi_e_mailings     => "checked",
        mmi_snail_mailings => "checked",
        share_mailings     => "checked",
        safety_form        => "",
        inactive       => "",
        deceased       => "",
        affil_table    => affil_table($c),
        form_action    => "create_do",
        template       => "person/create_edit.tt2",
    );
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    for my $k (keys %hash) {
        delete $hash{$k} if $k =~ m{^aff\d+$};
    }
    $hash{st_prov} = uc $hash{st_prov};
    $hash{zip_post} = uc $hash{zip_post};

    # since unchecked checkboxes are not sent...
    for my $f (qw/
        e_mailings
        snail_mailings
        mmi_e_mailings
        mmi_snail_mailings
        share_mailings
        inactive
        deceased
        safety_form
    /) {
        $hash{$f} = "" unless exists $hash{$f};
    }
    if ($hash{deceased}) {
        $hash{inactive} = 'yes';
    }
    @mess = ();
    $hash{akey} = nsquish($hash{addr1}, $hash{addr2}, $hash{zip_post});

    # normalize telephone number format
    for my $f (qw/
        tel_home
        tel_work
        tel_cell
    /) {
        next if $hash{$f} =~ m{\d\d\d-\d\d\d-\d\d\d\d};
        my $tmp = $hash{$f};
        $tmp =~ s{\D}{}g;
        if (length($tmp) == 10) {
            $hash{$f} = substr($tmp, 0, 3) . "-"
                      . substr($tmp, 3, 3) . "-"
                      . substr($tmp, 6, 4)
        }
    }

    if (empty($hash{last})) {
        push @mess, "Last name cannot be blank.";
    }
    if (empty($hash{first})) {
        push @mess, "First name cannot be blank.";
    }
    # for data from the temple we don't know the gender
    # it's only needed when doing a register.
    #
    #if ($hash{sex} ne 'F' && $hash{sex} ne 'M') {
    #    push @mess, "You must specify Male or Female: $hash{first}"
    #              # not really needed - hangs if no connection
    #              # " - "
    #              # . _what_gender($hash{first})
    #              ;
    #}
    if ($hash{addr1} && usa($hash{country}) && ! valid_state($hash{st_prov})) {
        push @mess, "Invalid state: $hash{st_prov}";
    }
    if ($hash{email} && ! valid_email($hash{email})) {
        push @mess, "Invalid email: $hash{email}";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "person/error.tt2";
    }
}

#
# which affiliations are checked?
#
sub _get_affils {
    my ($c, $id) = @_;

    my @cur_affils = grep { s/^aff(\d+)/$1/ }
                     $c->request->param;
    for my $ca (@cur_affils) {
        model($c, 'AffilPerson')->create({
            a_id => $ca,
            p_id => $id,
        });
    }
}

#
# look for possible duplicates and give a warning.
# I know it would be better to catch a possible duplicate and prevent
# it from being created AT ALL but that's more work.
# Perhaps later.
#
sub _get_dups {
    my ($c, $id, $p) = @_;

    my $last  = $p->last;
    my $first = $p->first;
    my $akey  = $p->akey;
    my @dups = model($c, 'Person')->search(
        {
            last  => $last,
            first => $first,
            id    => { "!=", $id },     # but not ourselves
        },
    );
    if (@dups) {
        # we have at least two duplicate names.
        # ??? what to do???
    }
    my $Clast  = substr($last, 0, 1);
    my $Cfirst = substr($first, 0, 1);
    push @dups, model($c, 'Person')->search(
        {
            last  => { 'like' => "$Clast%"  },
            first => { 'like' => "$Cfirst%" },
            akey  => $p->akey,
            id    => { "!=", $id },     # but not ourselves
        }
    );
    my %seen;
    @dups = grep { !$seen{$_->id}++; } @dups;   # undup possible dup dups :)
    my $dups = "";
    for my $d (@dups) {
        $dups .= _view_person($d) . ", ";
    }
    if ($dups) {
        $dups =~ s{, $}{};     # final ', '
        my $pl = (@dups == 1)? "": "s";
        $dups = " - Possible duplicate$pl: $dups";
    }
    $dups;
}

#
#
#
sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;

    # If first, last, sanskrit are all the same case
    # do a normalization to mixed case.
    # Only do this on first creation, not update.
    #
    for my $n (qw/ first last sanskrit /) {
        $hash{$n} = normalize($hash{$n});
    }
    my $today_d8 = tt_today($c)->as_d8();
    my ($type, $fname) = split m{/}, $hash{fname};
    delete $hash{fname};
    my $p = model($c, 'Person')->create({
        %hash,
        date_updat => $today_d8,
        date_entrd => $today_d8,
    });
    if ($fname) {
        my $dir = "root/static/${type}_done/"
                . today()->format("%Y-%m")
                ;
        mkdir $dir unless -d $dir;
        rename "root/static/$type/$fname",
               "$dir/$fname";
    }
    my $id = $p->id();
    _get_affils($c, $id);
    $c->flash->{message} = "Created " . _view_person($p)
                         . _get_dups($c, $id, $p)
                         . ".";
    $c->response->redirect($c->uri_for('/person/search'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Person')->find($id);
    my $sex = $p->sex() || "";
    stash($c,
        person         => $p,
        sex_female     => ($sex eq "F")? "checked": "",
        sex_male       => ($sex eq "M")? "checked": "",
        inactive       => (      $p->inactive())? "checked": "",
        deceased       => (      $p->deceased())? "checked": "",
        e_mailings     => (    $p->e_mailings())? "checked": "",
        snail_mailings => ($p->snail_mailings())? "checked": "",
        mmi_e_mailings     => (    $p->mmi_e_mailings())? "checked": "",
        mmi_snail_mailings => ($p->mmi_snail_mailings())? "checked": "",
        share_mailings => ($p->share_mailings())? "checked": "",
        safety_form    => (   $p->safety_form())? "checked": "",
        affil_table    => affil_table($c, $p->affils()),
        form_action    => "update_do/$id",
        template       => "person/create_edit.tt2",
    );
}

#
# currently there's no way to know which fields changed
# so assume they all did.  DBIx::Class is smart about this.
# can we be smart about affils???  yes, see ZZ below.
#
# check for dups???
#
sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    my $p = model($c, 'Person')->find($id);
    my ($type, $fname) = split m{/}, $hash{fname};
    delete $hash{fname};
    $p->update({
        %hash,
        date_updat => tt_today($c)->as_d8(),
    });
    if ($fname) {
        my $dir = "root/static/${type}_done/"
                . today()->format("%Y-%m")
                ;
        mkdir $dir unless -d $dir;
        rename "root/static/$type/$fname",
               "$dir/$fname";
    }
    # delete all old affiliations and create the new ones.
    model($c, 'AffilPerson')->search(
        { p_id => $id },
    )->delete();
    _get_affils($c, $id);
    #
    # in case this person was partnered we must
    # update the partner's address and home phone as well.
    #
    if ($p->partner) {
        $p->partner->update({
            addr1    => $hash{addr1},
            addr2    => $hash{addr2},
            city     => $hash{city},
            st_prov  => $hash{st_prov},
            zip_post => $hash{zip_post},
            country  => $hash{country},
            akey     => $hash{akey},
            tel_home => $hash{tel_home},
        });
    }

    my $msg = _view_person($p);
    my $pronoun = (defined $p->sex() and $p->sex() eq "M")? "his": "her";
    my $verb = "was";
    if ($p->partner) {
        $msg .= " and $pronoun partner "
              . _view_person($p->partner);
        $verb = "were"
    }
    $msg .= " $verb updated";
    $c->flash->{message} = $msg
                         . _get_dups($c, $id, $p)
                         . ".";
    $c->response->redirect($c->uri_for('/person/search'));
}

sub separate : Local {
    my ($self, $c, $id) = @_;
    my $p   = model($c, 'Person')->find($id);
    my $sps = $p->partner;
    #my $sps = model($c, 'Person')->find($p->id_sps());
    $p->update({
        id_sps     => 0,
        date_updat => today()->as_d8(),
    });
    $sps->update({
        id_sps     => 0,
        date_updat => tt_today($c)->as_d8(),
    });
    $c->response->redirect($c->uri_for("/person/view/$id"));
}

sub partner : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Person')->find($id);
    $c->stash->{person} = $p;
    $c->stash->{template} = "person/partner.tt2";
}

sub partner_with : Local {
    my ($self, $c, $id) = @_;

    my $p1 = model($c, 'Person')->find($id);
    my $first = trim($c->request->params->{first});
    my $last  = trim($c->request->params->{last});
    my (@people) = model($c, 'Person')->search(
        {
            first => $first,
            last  => $last,
        },
    );
    my $today = tt_today($c)->as_d8();
    if (@people == 1) {
        my $p2 = $people[0];
        if ($p2->partner) {
            $c->flash->{message} = $p2->first . " " . $p2->last
                                 . " is already partnered!";
            $c->response->redirect($c->uri_for("/person/search"));
        }
        else {
            $p1->update({
                id_sps     => $p2->id,
                date_updat => $today,
            });
            # partner #2 with automatically gets partner #1's address.
            # if they don't live together they don't get
            # to be partnered - in the mlist sense anyway.
            # is this discriminatory?
            $p2->update({
                id_sps     => $p1->id,
                addr1      => $p1->addr1,
                addr2      => $p1->addr2,
                city       => $p1->city,
                st_prov    => $p1->st_prov,
                zip_post   => $p1->zip_post,
                country    => $p1->country,
                tel_home   => $p1->tel_home,
                date_updat => $today,
            });
            $c->flash->{message} = "Partnered"
                                 . " " . _view_person($p1)
                                 . " with"
                                 . " " . _view_person($p2)
                                 . ".";
        }
        $c->response->redirect($c->uri_for("/person/search"));
    }
    else {
        $c->stash->{message} = $first . " " . $last
                             . " was not found - create them?";
        $c->stash->{form_action} = "/person/mkpartner/"
                                  . $id . "/"
                                  . $first . "/"
                                  . $last;

        $c->stash->{template} = "yes_no.tt2";
        return;
    }
}

sub mkpartner : Local {
    my ($self, $c, $id, $first, $last) = @_;

    my $p1 = model($c, 'Person')->find($id);
    if (! $c->request->params->{yes}) {
        $c->flash->{message} = "The partnering of "
                              . _view_person($p1)
                              . " was cancelled.";
        $c->response->redirect($c->uri_for("/person/search"));
        return;
    }
    my $addr1    = $p1->addr1;
    my $addr2    = $p1->addr2;
    my $zip_post = $p1->zip_post;

    my $sex2 = ($p1->sex eq "M")? "F": "M";   # usually, not always
    my $today = tt_today($c)->as_d8();
    my $p2 = model($c, 'Person')->create({
        last     => $last,
        first    => $first,
        sanskrit => '',
        sex      => $sex2,
        addr1    => $addr1,
        addr2    => $addr2,
        city     => $p1->city,
        st_prov  => $p1->st_prov,
        zip_post => $zip_post,
        country  => $p1->country,
        akey     => nsquish($addr1, $addr2, $zip_post),
        tel_home => $p1->tel_home,
        id_sps   => $p1->id,
        date_entrd => $today,
        date_updat => $today,
    });
    $p1->update({
        id_sps     => $p2->id,
        date_updat => $today,
    });
    my $pronoun = ($sex2 eq 'M')? "him": "her";
    $c->flash->{message} = "Created"
                         . " " . _view_person($p2)
                         . " and partnered $pronoun with"
                         . " " . _view_person($p1)
                         . ".";
    $c->response->redirect($c->uri_for("/person/search"));
}

# show all future (and current - up to today) programs
# in alphabetical order and allow one to be chosen.
# if one of your roles is mmi_admin include
# mmi programs otherwise not.
# do not include resident programs.
#
sub register1 : Local {
    my ($self, $c, $id, $resident) = @_;

    my $today = tt_today($c)->as_d8();
    my $person = model($c, 'Person')->find($id);
    if (!($person->sex() && $person->sex() =~ m{[MF]})) {
        error($c,
            'Sorry, you must set a gender for '
                . $person->first() . " " . $person->last()
                . ' before you can register them for a program.',
            'gen_error.tt2',
        );
        return;
    }
    my @cond = ();
    if (! $c->check_user_roles('mmi_admin')) {
        #
        # not an mmi_admin so
        # show only MMC sponsored programs.
        #
        push @cond, (
            school => 0,
        );
    }
    if ($resident) {
        @cond = (
            'category.name' => { '!=' => 'Normal' },
        );
    }
    else {
        push @cond, (
            'category.name' => 'Normal',
        );
    }
    #
    # fancy footwork needed (me instead of program below)
    # because both program and category have a name column.
    #
    my @programs = model($c, 'Program')->search(
        {
            edate     => { '>='      => $today               },
            'me.name' => { -not_like => '%personal%retreat%' },
            @cond,
        },
        {
            join     => [ qw/ category   / ],
            prefetch => [ qw/ category   / ],
            order_by => [ qw/ sdate me.name / ]
        },
    );
    if (!$resident) {
        my (@personal_retreats) = model($c, 'Program')->search(
            {
                name  => { like => '%personal%retreat%' },
                edate => { '>=' => $today               },
            },
            { order_by => 'sdate' },
        );
        unshift @programs, @personal_retreats;
    }
    $c->stash->{person}   = $person;
    $c->stash->{programs} = \@programs;
    $c->stash->{template} = "person/register.tt2";
}

sub undup : Local {
    my ($self, $c, $ids) = @_;

    my @people = map { model($c, 'Person')->find($_) }
                 split /-/, $ids;
    $c->stash->{people} = \@people;
    $c->stash->{template} = "person/undup.tt2";
}

sub undup_do : Local {
    my ($self, $c) = @_;

    my $content = "";
    my $primary = 0;
    my @merged = ();
    my @non_blank = ();
    my $partner = 0;
    my $unknown = 0;
    FIELD:
    for my $id ($c->request->param) {
        my $c = $c->request->params->{$id};
        next FIELD unless defined $c && $c =~ /\S/;
        push @non_blank, $id;
        if ($c eq 'P') {
            $primary = $id;
        }
        elsif ($c eq 'm') {
            push @merged, $id;
        }
        elsif ($c eq 'p') {
            $partner = $id;
        }
        else {
            $unknown = 1;
        }
    }
    if ($primary && $partner && @merged == 0 && ! $unknown) {
        my $p = model($c, 'Person')->find($primary);
        $p->update({
            id_sps => $partner,
        });
        model($c, 'Person')->search({
            id => $partner,
        })->update({
            id_sps   => $primary,
            addr1    => $p->addr1,
            addr2    => $p->addr2,
            city     => $p->city,
            st_prov  => $p->st_prov,
            zip_post => $p->zip_post,
            country  => $p->country,
            tel_home => $p->tel_home,
        });
        $c->response->redirect($c->uri_for("/person/view/$primary"));
        return;
    }
    if ($unknown) {
        # narrow them down...
        undup($self, $c, join '-', @non_blank);
        return;
    }
    unless (@merged && $primary) {
        # error
        $c->stash->{template} = "person/undup_err.tt2";
        return;
    }
    #
    # for each person to merge, take their registrations
    # and modify the person_id field to be the primary id.
    # do the same with donations and credits.
    #
    # Unpartner the merged person and then any
    # affil_person, leader, member (and related) records connected
    # to the merged person should be deleted.
    #
    # sorry to delete them but too much trouble would ensue if
    # the primary person was ALSO a leader or member or if they
    # had the same affils.
    #
    # actually, prohibit doing this at all if a merged person
    # is a member.
    #
    # then delete the merged person record.
    #
    for my $mid (@merged) {
        if (my ($member) = model($c, 'Member')->search({
                               person_id => $mid,
                           })
        ) {
            my ($person) = model($c, 'Person')->find($mid);
            error($c,
                "Cannot merge " . $person->first() . " " . $person->last()
                . " because "
                . ($person->sex() eq 'M'? "he": "she")
                . " is a member.",
                'gen_error.tt2',
            );
            return;
        }
    }
    for my $mid (@merged) {
        for my $table (qw/ Registration Credit Donation /) {
            model($c, $table)->search({
                person_id => $mid,
            })->update({
                person_id => $primary,
            });
        }
        # partner, if any
        model($c, 'Person')->search({
            id_sps => $mid,
        })->update({
            id_sps => 0,
        });
        model($c, 'AffilPerson')->search({
            p_id => $mid,
        })->delete();
        model($c, 'Leader')->search({
            person_id => $mid,
        })->delete();
        # leader image???
        if (my ($member) = model($c, 'Member')->search({
                               person_id => $mid,
                           })
        ) {
            $member->delete();      # should cascade
        }
        # finally, delete the person we are merging
        model($c, 'Person')->search({
            id => $mid,
        })->delete();
    }
    $c->response->redirect($c->uri_for("/person/view/$primary"));
}

sub set_gender : Local {
    my ($self, $c, $id, $gender) = @_;

    model($c, 'Person')->search({
        id => $id,
    })->update({
        sex => $gender,
    });
    $c->response->redirect($c->uri_for("/person/view/$id"));
}

sub undup_akey : Local {
    my ($self, $c, $addr) = @_;
    
    undup($self, $c,
          join '-',
          map { $_->id }
          model($c, 'Person')->search({
              akey => $addr,
          })
         );
          
}

sub list_mmi_payment : Local {
    my ($self, $c, $id, $show_gl) = @_;

    my $person = $c->stash->{person} = model($c, 'Person')->find($id);
    my $tot = 0;
    for my $pay ($person->mmi_payments()) {
        $tot += $pay->amount();
    }
    stash($c,
        time      => scalar(localtime),
        mmi_print => 0,
        show_gl   => $show_gl,
        tot       => commify($tot),
        template  => "person/mmi_payments.tt2",
    );
}

sub list_mmi_payment_print : Local {
    my ($self, $c, $id) = @_;

    my $person = model($c, 'Person')->find($id);
    my $tot = 0;
    for my $pay ($person->mmi_payments()) {
        $tot += $pay->amount();
    }
    my $html = "";
    my $tt = Template->new({
        INCLUDE_PATH => 'root/src',
        EVAL_PERL    => 0,
    });
    my $stash = {
        mmi_print => 1,
        tot       => commify($tot),
        person    => $person,
        today     => today(),
        time      => scalar(localtime),
    };
    $tt->process(
        "person/mmi_payments.tt2",   # template
        $stash,               # variables
        \$html,               # output
    );
    $c->res->output($html);
    return;
}

sub del_mmi_payment : Local {
    my ($self, $c, $payment_id, $from) = @_;
    
    my $pay = model($c, 'MMIPayment')->find($payment_id);
    $pay->delete();
    my $reg = $pay->registration();
    $reg->calc_balance();
    if ($from eq 'reg') {
        $c->response->redirect(
            $c->uri_for("/registration/view/" . $reg->id()
            )
        );
    }
    else {
        $c->response->redirect(
            $c->uri_for("/person/list_mmi_payment/"
                        . $pay->person_id)
        );
    }
}

sub create_mmi_payment : Local {
    my ($self, $c, $reg_id, $person_id, $from) = @_;
    
    if (tt_today($c)->as_d8() eq $string{last_mmi_deposit_date}) {
        error($c,
              'Since a deposit was just done for MMI'
                  . ' please make this payment tomorrow instead.',
              'gen_error.tt2');
        return;
    }
    my $reg = model($c, 'Registration')->find($reg_id);
    if (empty($reg->program->glnum())) {
        error($c,
            $reg->program->name() . " does not have a GL Number.  Please fix.",
            "gen_error.tt2",
        );
        return;
    }
    stash($c,
        from     => $from,
        message  => payment_warning('mmi'),
        person   => model($c, 'Person')->find($person_id),
        reg      => $reg,
        template => "person/create_mmi_payment.tt2",
    );
}

sub create_mmi_payment_do : Local {
    my ($self, $c, $reg_id, $person_id) = @_;

    my $amount = trim($c->request->params->{amount});
    if (invalid_amount($amount)) {
        error($c,
            "Illegal amount: $amount",
            "registration/error.tt2",
        );
        return;
    }
    my $for_what = $c->request->params->{for_what};
    my $dcm_reg = dcm_registration($c, $person_id);
    my $reg = model($c, 'Registration')->find($reg_id);
    my $glnum;
    if (ref($dcm_reg)) {
        # this person is enrolled in a DCM program
        #
        my $program = $dcm_reg->program();

        my $sdate = $program->sdate_obj();
        my $m = $sdate->month();
        $glnum = $for_what
               . $program->school()
               . $sdate->format("%y")
               . ((1 <= $m && $m <=  9)? $m
                  :          ($m == 10)? 'X'
                  :          ($m == 11)? 'Y'
                  :                      'Z'
                 )
               . $program->level()
               ;
    }
    else {
        # this person is an auditor.
        # (OR they are enrolled in more than one DCM program! :( )
        #
        # we use the glnum of the program itself (plus 'for_what').
        #
        if ($for_what == 3 || $for_what == 4) {
            $c->stash->{mess} = "Since this person is an Auditor the payment<br>cannot be a fee for Application or Registration.";
            $c->stash->{template} = "gen_error.tt2";
            return;
        }
        $glnum = $c->request->params->{for_what}
               . $reg->program->glnum();
    }

    my $the_date = tt_today($c)->as_d8();
    if ($the_date eq $string{last_mmi_deposit_date}) {
        $the_date = (tt_today($c)+1)->as_d8();
    }
    model($c, 'MMIPayment')->create({
        person_id => $person_id,
        amount    => $amount,
        type      => $c->request->params->{type},
        glnum     => $glnum,
        the_date  => $the_date,
        reg_id    => $reg_id,
        note      => $c->request->params->{note},
    });
    $reg->calc_balance();
    if ($c->request->params->{from} eq 'edit_dollar') {
        $c->response->redirect(
            $c->uri_for("/registration/edit_dollar/$reg_id")
        );
    }
    else {
        $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
    }
}

sub update_mmi_payment : Local {
    my ($self, $c, $pay_id, $from) = @_;

    my $pay = model($c, 'MMIPayment')->find($pay_id);
    my $type = $pay->type();
    my $type_opts = "";
    for my $t (qw/ D C S /) {
        $type_opts .= "<option value=$t"
                   .  ($type eq $t? " selected"
                      :             ""         )
                   .  ">"
                   .  $string{"payment_$t"}
                   .  "\n";
                   ;
    }
    my $for_what = substr($pay->glnum(), 0, 1);
    my $for_what_opts = "";
    my $n = 1;
    for my $wh ('Tuition',
                'Meals and Lodging',
                'Application Fee',
                'Registration Fee',
                'Other',
    ) {
        $for_what_opts .= "<option value=$n"
                       .  ($for_what == $n? " selected"
                          :                 ""         )
                       .  ">$wh\n"
                       ;
        ++$n;
    }
    stash($c,
        from          => $from,
        type_opts     => $type_opts,
        for_what_opts => $for_what_opts,
        pay           => $pay,
        template      => 'person/update_mmi_payment.tt2',
    );
}

sub update_mmi_payment_do : Local {
    my ($self, $c, $pay_id) = @_;

    my $pay = model($c, 'MMIPayment')->find($pay_id);
    my $amount = trim($c->request->params->{amount});
    if (invalid_amount($amount)) {
        error($c,
            "Illegal amount: $amount",
            "registration/error.tt2",
        );
        return;
    }
    my $the_dt = trim($c->request->params->{the_date});
    my $dt = date($the_dt);
    if (! $dt) {
        error($c,
            "Illegal date: $the_dt",
            'gen_error.tt2',
        );
        return;
    }
    $pay->update({
        amount   => $amount,
        the_date => $dt->as_d8(),
        type     => $c->request->params->{type},
        glnum    => $c->request->params->{for_what}
                  . substr($pay->glnum(), 1),
        note     => $c->request->params->{note},
    });
    $pay->registration->calc_balance();
    if ($c->request->params->{from} eq 'reg') {
        $c->response->redirect(
            $c->uri_for("/registration/view/" . $pay->reg_id())
        );;
    }
    else {
        $c->response->redirect(
            $c->uri_for("/person/list_mmi_payment/" . $pay->person_id())
        );
    }
}

sub get_addr : Local {
    my ($self, $c, $first, $last) = @_;

    my @persons = model($c, 'Person')->search({
        first => $first,
        last  => $last,
    });
    my $addr = "not found";
    if (@persons) {
        my $p = $persons[0];
        $addr = join '|',
                $p->addr1(),
                $p->addr2(),
                $p->city(),
                $p->st_prov(),
                $p->zip_post(),
                $p->country(),
                $p->tel_home(),
                $p->tel_work(),
                $p->tel_cell(),
                $p->email(),
                ;
    }
    $c->res->output($addr);
}

#
# toggle inactive on/off
#
sub inactive : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Person')->find($id);
    $p->update({
        inactive => ($p->inactive())? '': 'yes',
    });
    $c->response->redirect($c->uri_for("/person/view/$id"));
}

sub get_gender : Local {
    my ($self, $c, $name) = @_;

    my $html = get("http://www.gpeters.com/names/baby-names.php?"
                  ."name=" . $name);
    my ($likelihood, $gender) =
        $html =~ m{popular usage, it is <b>([\d.]+).*?to be a (\w+)'s};
    my %name = qw(
        girl F
        boy  M
    );
    my $rc = 'F';
    if ($gender) {
        $rc = $name{$gender};
    }
    elsif (($gender) = $html =~ m{It's a (.*?)!}) {
        $rc = $name{$gender};
    }
    $c->res->output($rc);
    return;
}

sub online : Local {
    my ($self, $c) = @_;

    my @requests = ();
    for my $f (<root/static/mlist/*>) {
        my $href = {};
        ($href->{num}) = $f =~ m{(\d+)};
        open my $in, "<", $f
            or die "cannot open $f: $!\n";
        my ($type, $send) = ("", 0);
        while (my $line = <$in>) {
            chomp $line;
            my ($key, $val) = $line =~ m{^(\w+)\s+(.*)};
            if ($key eq 'type') {
                $val = uc $val;
            }
            $href->{$key} = $val;
        }
        close $in;
        my $mtime = (stat($f))[9];
        my ($min, $hour, $day, $mon, $year) = (localtime($mtime))[1 .. 5];
        $year += 1900;
        ++$mon;
        $href->{date} = date($year, $mon, $day);
        $href->{time} = get_time(sprintf("%02d%02d", $hour, $min));
        push @requests, $href;
    }
    for my $f (<root/static/temple/*>) {
        my $href = {};
        ($href->{num}) = $f =~ m{(\d+)};
        open my $in, "<", $f
            or die "cannot open $f: $!\n";
        while (my $line = <$in>) {
            my ($first, $last) = split m{\|}, $line;
            $href->{first} = $first;
            $href->{last} = $last;
            $href->{type} = 'Temple';
        }
        close $in;
        my $mtime = (stat($f))[9];
        my ($min, $hour, $day, $mon, $year) = (localtime($mtime))[1 .. 5];
        $year += 1900;
        ++$mon;
        $href->{date} = date($year, $mon, $day);
        $href->{time} = get_time(sprintf("%02d%02d", $hour, $min));
        push @requests, $href;
    }
    stash($c,
        requests => \@requests,
        template => 'person/online.tt2',
    );
}

sub grab_new : Local {
    my ($self, $c) = @_;
    system("grab wait");
    $c->response->redirect($c->uri_for("/person/online"));
}


sub online_add : Local {
    my ($self, $c, $type, $num) = @_;

    my $subdir = $type eq 'Temple'? 'temple'
                 :                  'mlist'
                 ;
    my $fname = "root/static/$subdir/$num";
    my $in;
    if (! open $in, "<", $fname) {
        error($c,
            "Cannot find online $subdir file $num.",
            'gen_error.tt2',
        );
        return;
    }
    my %P;
    my @affils = ();
    if ($type eq 'Temple') {
        my $line = <$in>;
        chomp $line;
        my ($first, $last, $email, $phone, $addr1, $addr2, $city, $state, $zip)
            = split m{\|}, $line;
        $P{first} = normalize($first);
        $P{last}  = normalize($last);
        $P{email} = $email;
        $P{tel_cell} = $phone;
        $P{addr1} = $addr1;
        $P{addr2} = $addr2;
        $P{city}  = $city;
        $P{st_prov}  = uc $state;
        $P{zip_post} = $zip;
        $P{sex} = '';           # gender is unknown - leave it unset
        @affils = model($c, 'Affil')->search({
            descrip => { 'like' => '%Temple%Guest%' },
        });
        $P{e_mailings} = 'yes';
        $P{snail_mailings} = '';
        $P{mmi_e_mailings} = 'yes';
        $P{mmi_snail_mailings} = '';
        $P{share_mailings} = 'yes';     # why not
    }
    else {
        while (my $line = <$in>) {
            chomp $line;
            my ($key, $val) = $line =~ m{^(\w+)\s+(.*)};
            $P{$key} = $val;
        }
        close $in;
        $P{first} = normalize($P{first});
        $P{last} = normalize($P{last});
        $P{addr1} = $P{street};
        $P{addr2} = '';
        my $type = $P{type};
        my $interest = $P{interest};
        for my $k (qw/ cell home work /) {
            $P{"tel_$k"} = $P{$k};
        }
        $P{sex} = $P{gender} eq 'female'? 'F': 'M';
        $P{comment} = $P{request};
        $P{comment} =~ s{NEWLINE}{\n}g;
        for my $k (qw/
            street type interest
            cell home work gender
            request email2
        /) {
            delete $P{$k};
        }
        if ($type eq 'mmi') {
            if ($interest eq 'All Schools') {
                @affils = model($c, 'Affil')->search({
                    -and => [
                        descrip => { 'like' => 'MMI%' },
                        descrip => { 'not_like' => '%Discount%' },
                    ],
                });
            }
            else {
                @affils = model($c, 'Affil')->search({
                    descrip => { 'like' => "MMI%$interest" },
                });
            }
        }
    }
    my @people = model($c, 'Person')->search({
        first => $P{first},
        last  => $P{last},
    });
    if (@people == 0) {
        stash($c,
            e_mailings         => ($P{e_mailings}        )? "checked": "",
            snail_mailings     => ($P{snail_mailings}    )? "checked": "",
            mmi_e_mailings     => ($P{mmi_e_mailings}    )? "checked": "",
            mmi_snail_mailings => ($P{mmi_snail_mailings})? "checked": "",
            share_mailings     => ($P{share_mailings}    )? "checked": "",
            fname          => "$subdir/$num",
            person         => \%P,
            sex_female     => ($P{sex} eq "F")? "checked": "",
            sex_male       => ($P{sex} eq "M")? "checked": "",
            inactive       => "",
            deceased       => "",
            affil_table    => affil_table($c, @affils),
            form_action    => "create_do",
            template       => "person/create_edit.tt2",
        );
    }
    elsif (@people == 1) {
        my $p = $people[0];
        stash($c,
            e_mailings         => ($P{e_mailings}        )? "checked": "",
            snail_mailings     => ($P{snail_mailings}    )? "checked": "",
            mmi_e_mailings     => ($P{mmi_e_mailings}    )? "checked": "",
            mmi_snail_mailings => ($P{mmi_snail_mailings})? "checked": "",
            share_mailings     => ($P{share_mailings}    )? "checked": "",
            fname              => "$subdir/$num",
            person => {
                first     => $P{first},
                last      => $P{last},
                sanskrit  => $p->sanskrit(),
                addr1     => $P{addr1} || $p->addr1(),
                addr2     => $p->addr2(),
                city      => $P{city} || $p->city(),
                st_prov   => $P{st_prov} || $p->st_prov(),
                zip_post  => $P{zip_post} || $p->zip_post(),
                country   => $P{country} || $p->country(),
                email     => $P{email} || $p->email(),
                tel_cell  => $P{tel_cell} || $p->tel_cell(),
                tel_home  => $P{tel_home} || $p->tel_home(),
                tel_work  => $P{tel_work} || $p->tel_work(),
                comment   => $P{comment} || $p->comment(),
            },
            sex_female => ($P{sex} eq "F")? "checked": "",
            sex_male   => ($P{sex} eq "M")? "checked": "",
            inactive   => "",
            deceased   => "",
            affil_table => affil_table($c, $p->affils(), @affils),
            form_action => "update_do/" . $p->id(),
            template    => "person/create_edit.tt2",
        );
    }
    else {
        error($c,
              "$P{first} $P{last} needs unduplicating first!",
              'gen_error.tt2'
        );
    }
}

sub online_del : Local {
    my ($self, $c, $type, $num) = @_;
    my $subdir = ($type eq 'Temple')? 'temple'
                 :                    'mlist'
                 ;
    my $dir = "root/static/${subdir}_done/"
            . today()->format("%Y-%m")
            ;
    mkdir $dir unless -d $dir;
    rename "root/static/$subdir/$num",
           "$dir/$num";
    $c->response->redirect($c->uri_for("/person/online"));
}

1;
