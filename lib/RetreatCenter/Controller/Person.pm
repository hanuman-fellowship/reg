#
# TODO: something needs tidying up here.
# search for _done and fname
# I think these are obsolete now.
#
use strict;
use warnings;
package RetreatCenter::Controller::Person;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    get_string
    affil_table
    trim
    empty
    nsquish
    valid_email
    model
    tt_today
    commify
    long_term_registration
    payment_warning
    normalize
    stash
    error
    invalid_amount
    email_letter
    calc_mmi_glnum
    get_now
    rand6
    charges_and_payments_options
    strip_nl
    time_travel_class
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
    %system_affil_id_for
/;
use USState;
use LWP::Simple;
use Template;
use Data::Dumper;
use Net::FTP;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('search');
}

sub _view_person {
    my ($p) = @_;
    "<a href='/person/view/" . $p->id . "'>"
    . $p->name()
    . "</a>";
}

sub search : Local {
    my ($self, $c, $pattern, $field, $nrecs) = @_;

    if ($pattern && $pattern eq '__expired__') {
        # special case - $field a number of days
        my $msg = ($field <= 1)? "Change it TODAY"
                 :               "You have $field days to change it"
                 ;
        $msg .= " or you will be locked out.<p class=p2>";
        $msg .= "You can change it <a href=/user/profile_password>here</a>.<p class=p2>";
        $c->stash->{message}  = "<b>Your password has expired!!</b><br>$msg";
    }
    else {
        if ($pattern) {
            $c->stash->{message}  = "No one found matching '$pattern'.";
        }
        $c->stash->{pattern} = $pattern;
        if (! $field) {
            $c->stash->{last_selected} = "selected";
        }
        for my $f (qw/ 
            last sanskrit zip_post email first tel_home country rec_num
        /) {
            if (defined $field && $field eq $f) {
                $c->stash->{"$f\_selected"} = "selected";
            }
        }
    }
    stash($c,
        time_travel_class($c),
        pg_title => "People Search",
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
    if ($field eq 'rec_num') {
        $c->response->redirect($c->uri_for("/person/view/$orig_pattern"));
        return;    
    }
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
    elsif ($pattern =~ m{ \A \s* id \s* = \s* (\d+) \s* \z }xms) {
        $search_ref = {
            id => $1,
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
    stash($c,
        time_travel_class($c),
        field => $field eq 'tel_home'? 'tel_home': 'email',
        ids => join('-', map { $_->id } @people),
        people => \@people,
        field_desc => $field eq 'tel_home'? 'Home Phone'
                     :                      ucfirst $field,
        pattern => $orig_pattern,
        template => 'person/search_result.tt2',
    );
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
    my $name = $p->name();
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
        time_travel_class($c),
        person   => $p,
        pg_title => $p->name(),
        sex      => (!defined $sex || !$sex)? "Not Reported"
                   :($sex eq "M"           )? "Male"
                   :($sex eq "F"           )? "Female"
                   :($sex eq "X"           )? "Non-Binary"
                   :                          "Not Reported",
        template => "person/view.tt2",
    );
}

sub touch : Local {
    my ($self, $c, $id) = @_;
    model($c, 'Person')->find($id)->update({
        date_updat => today->as_d8(),
    });
    $c->response->redirect($c->uri_for("/person/view/$id"));
}

sub create : Local {
    my ($self, $c) = @_;

    stash($c,
        e_mailings         => "checked",
        snail_mailings     => "checked",
        share_mailings     => "checked",
        safety_form        => "",
        waiver_signed      => "",
        inactive       => "",
        deceased       => "",
        affil_table    => affil_table($c, 0),
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
        share_mailings
        inactive
        deceased
        safety_form
        waiver_signed
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
# Later: I've tried ...  we'll leave this here anyway.
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
    my ($type, $fname);
    my @temple;
    if (exists $hash{fname}) {
        ($type, $fname) = split m{/}, $hash{fname};
        delete $hash{fname};
        if ($type eq 'temple') {
            @temple = (temple_id => $fname);
        }
    }
    my $p = model($c, 'Person')->create({
        %hash,
        date_updat  => $today_d8,
        date_entrd  => $today_d8,
        secure_code => rand6($c),
        @temple,
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
        sex_non_binary => ($sex eq "X")? "checked": "",
        inactive       => (      $p->inactive())? "checked": "",
        deceased       => (      $p->deceased())? "checked": "",
        e_mailings     => (    $p->e_mailings())? "checked": "",
        snail_mailings => ($p->snail_mailings())? "checked": "",
        share_mailings => ($p->share_mailings())? "checked": "",
        safety_form    => (   $p->safety_form())? "checked": "",
        waiver_signed  => ( $p->waiver_signed())? "checked": "",
        affil_table    => affil_table($c, 0, $p->affils()),
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
    my @temple;
    my ($type, $fname);
    if (exists $hash{fname}) {
        ($type, $fname) = split m{/}, $hash{fname};
        delete $hash{fname};
        if (defined $type && $type eq 'temple') {
            @temple = (temple_id => $fname);
        }
    }
    $p->update({
        %hash,
        @temple,
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
    # delete all existing affiliations
    # (but not ones that are system and not selectable)
    # and create the new ones.
    my @sys_affils = map { $_->id }
                     model($c, 'Affil')->search(
                         {
                             system => 'yes',
                             selectable => '',
                         },
                     );
    model($c, 'AffilPerson')->search(
        {
            p_id => $id,
            a_id => { -not_in => \@sys_affils },
        },
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
    my $verb = "was";
    if ($p->partner) {
        $msg .= " and their partner "
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
            $c->flash->{message} = $p2->name()
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
        date_entrd  => $today,
        date_updat  => $today,
        secure_code => rand6($c),
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
    $person->update({
        date_updat => today()->as_d8(),
    });

    if (!($person->sex() && $person->sex() =~ m{[MFX]})) {
        error($c,
            'Sorry, you must set a gender for '
                . $person->name()
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
            school_id => 1,
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
            cancelled => '',        # not cancelled, please
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
    stash($c,
        template => "person/register.tt2",
        person   => $person,
        programs => \@programs,
        resident => $resident,
    );
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
    # the affiliations of the merged person should be
    # put on the primary person if they're not there already.
    #
    # Unpartner the merged person and then any
    # leader, member (and related) records connected
    # to the merged person should be deleted.
    #
    # sorry to delete them but too much trouble would ensue if
    # the primary person was ALSO a leader or member.
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
                "Cannot merge " . $person->name()
                . " because "
                . ($person->sex() eq 'M'? "he": "she")
                . " is a member.",
                'gen_error.tt2',
            );
            return;
        }
    }
    my %primary_affils = map { $_->a_id => 1 }
                         model($c, 'AffilPerson')->search({
                             p_id => $primary,
                         });
    for my $mid (@merged) {
        for my $table (qw/ Registration Credit Donation MMIPayment /) {
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
        for my $m_a_id (map { $_->a_id }
                        model($c, 'AffilPerson')->search({
                            p_id => $mid,
                        })
        ) {
            if (! exists $primary_affils{$m_a_id}) {
                # add the merged person's affil to the primary
                model($c, 'AffilPerson')->create({
                    a_id => $m_a_id,
                    p_id => $primary,
                });
            }
        }
        # now we can delete all of the merged person's affils
        model($c, 'AffilPerson')->search({
            p_id => $mid,
        })->delete();
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

    my $person = model($c, 'Person')->find($id);
    my $tot = 0;
    for my $pay ($person->mmi_payments()) {
        $tot += $pay->amount();
    }
    stash($c,
        person    => $person,
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
    ) or die "error in processing template: "
             . $tt->error();
    $c->res->output($html);
    return;
}

sub del_mmi_payment : Local {
    my ($self, $c, $payment_id, $from) = @_;
    my $mmi_pay = model($c, 'MMIPayment')->find($payment_id);
    stash($c,
        mmi_pay    => $mmi_pay,
        from       => $from,
        template   => 'person/confirm_del_mmi_payment.tt2',
    );
}

sub del_mmi_payment_do : Local {
    my ($self, $c, $payment_id, $from) = @_;
    
    my $pay = model($c, 'MMIPayment')->find($payment_id);
    my $reg = $pay->registration();
    if ($c->request->params->{yes}) {
        my $amount = $pay->amount();
        my $for_what = $pay->for_what();
        $pay->delete();
        # add a Reg History record
        my @who_now = get_now($c);
        model($c, 'RegHistory')->create({
            reg_id   => $reg->id,
            what     => "Deleted Payment of \$" . commify($amount)
                      . " for $for_what",
            @who_now,
        });
        $reg->calc_balance();
    }
    if ($from eq 'reg') {
        $c->response->redirect(
            $c->uri_for("/registration/view/" . $reg->id())
        );
    }
    else {
        $c->response->redirect(
            $c->uri_for("/person/list_mmi_payment/" . $pay->person_id)
        );
    }
}

sub request_payment : Local {
    my ($self, $c, $reg_id, $person_id) = @_;

    my $reg = model($c, 'Registration')->find($reg_id);
    my $glnum = $reg->program->glnum();
    if (empty($glnum) || $glnum =~ m{XX}xms) {
        error($c,
            "The GL Number has not yet been assigned.",
            "gen_error.tt2",
        );
        return;
    }
    my $person = model($c, 'Person')->find($person_id);
    if (empty($person->email())) {
        error($c,
            $person->first() . " does not have an email address.  Please fix.",
            "gen_error.tt2",
        );
        return;
    }
    stash($c,
        message   => payment_warning('mmi'),
        person    => $person,
        reg       => $reg,
        for_what_opts => charges_and_payments_options(),
        template  => "person/request_payment.tt2",
    );
}

sub request_payment_do : Local {
    my ($self, $c, $reg_id, $person_id) = @_;

    my $amount = trim($c->request->params->{amount}) || '';
    if (invalid_amount($amount)) {
        error($c,
            "Illegal amount: $amount",
            "registration/error.tt2",
        );
        return;
    }
    my $org = $c->request->params->{org};
    if (! $org) {
        error($c,
            "Is this payment for MMC or MMI?",
            "registration/error.tt2",
        );
        return;
    }
    my $the_date = tt_today($c)->as_d8();
    my $note = $c->request->params->{note} || '';
    my $for_what = $c->request->params->{for_what};

    my $req_payment = model($c, 'RequestedPayment')->create({
        person_id => $person_id,
        org       => $org,
        amount    => $amount,
        for_what  => $for_what,
        the_date  => $the_date,
        reg_id    => $reg_id,
        note      => $note,
    });
    model($c, 'RegCharge')->create({
        reg_id    => $reg_id,
        user_id   => $c->user->obj->id(),
        the_date  => tt_today($c)->as_d8(),
        time      => get_time()->t24(),
        amount    => $amount,
        what      => $note,
        automatic => '',        # this charge will not be cleared
                                # when editing a registration.
        type      => $req_payment->for_what(),
            # The above setting of 'type' is correct.
            # The integer values for the 
            # 'for_what' field in the 'req_payment' table
            # match the 'type' field in the 'reg_charge' table.
    });
    my @who_now = get_now($c);
    push @who_now, reg_id => $reg_id;
    my $reg = model($c, 'Registration')->find($reg_id);
    RetreatCenter::Controller::Registration::_compute($c, $reg, 0, @who_now);
        # the above full qualifier indicates
        # that this sub should have been in Registration.pm instead. :(
    # Reg History record
    model($c, 'RegHistory')->create({
        reg_id   => $reg_id,
        what     => "Payment request of \$" . commify($amount)
                  . " to $org for "
                  . $req_payment->for_what_disp(),
        @who_now,
    });
    $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
}

# TODO: test the sending of the request
# ensure it arrives at BOTH mmi and mmc sites.
# Dumper? purge the old way.  signed and quest_email keys as well.
# req_pay (instead of req_mmi)
#     if no signed key make it Leslie, ditto for _from
# when good make link from req_mmi to req_pay and remove req_mmi
#     how will git manage this?
# copy req_pay to mmc site - with diff fingerprint
#    make this fingerprint dependent on /for_reg/req_mm[ic]_payment dir? -f?
# test payment at both sites at authorize.net, void the payments
# relay creates the proper transaction file?
#     i.e. moves the code file to the proper paid directory
# test grab_new - be careful to avoid running it when
#     kali is running as well...
#     perhaps temporarily handicap it to ONLY process req payments?
# test suite for Manjarika, Rachel/Leslie?
#     delete requests - does not delete the charge!
#     resending - removes the file at the remote site?
#     how about a date for the request to expire?
#     Put this in the email?  have cron job to purge expired ones?
#     remind them of the req_payment strings:
#          payment_request_signed, payment_request_from (fff lll <xxx@yyy.com>)
#
sub send_requests : Local {
    my ($self, $c, $reg_id, $resend_all) = @_;

    for my $org (qw/ MMC MMI /) {
        _send_requests($self, $c, $reg_id, $resend_all, $org);
    }
    $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
}

#
# this sub does a lot.
# for the registration
# it sees what existing payment requests there are
# for the given organization.  Some may have been sent
# already.  If 'resend_all' is true then all should be sent again.
# it generates a random 6 letter code ($code) and creates
# a file /tmp/$code with a Data::Dumper formatted structure
# that includes the person's name, address, ... and the requested
# total amount.
# this file is ftp'ed to the global web (mmc or mmi) in
# a well known place.
# an email is sent (optionally) to the person giving them
# a link to a CGI script along with the $code.  With this they
# can pay the given total amount.
# A RegHistory record is added.
#
sub _send_requests {
    my ($self, $c, $reg_id, $resend_all, $org, $no_email) = @_;
    my $reg = model($c, 'Registration')->find($reg_id);
    my $public = $reg->program->level->public();
    my $person = $reg->person();
    my $person_id = $person->id();
    my $name = $person->name();
    my $phone = $person->tel_home() || $person->tel_cell();
    my $email = $person->email();
    my $program_name = $reg->program->name();

    my $code = rand6($c);
    my $total = 0;
    my $py_desc = q{};
    my $tbl_py_desc = <<"EOH";
<table cellpadding=5>
<tr>
<th align=right>Amount</th>
<th align=left>For</th>
<th align=left>Note</th>
</tr>
EOH
    my $prog_glnum = $reg->program->glnum();
    my @old_codes;
    my $npayments = 0;
    PAYMENT:
    for my $py ($reg->req_payments()) {
        if ($py->org() ne $org) {
            # not for the current organization
            next PAYMENT;
        }
        if ($resend_all) {
            push @old_codes, $py->code();
        }
        elsif ($py->code()) {
            # if not resending
            # $py->code means
            # already sent but not yet gotten
            next PAYMENT;
        }
        ++$npayments;
        my $amt = commify($py->amount());
        my $note = $py->note();
        my $for  = $py->for_what_disp();
        $total += $py->amount();
        $py_desc .= join('|', $amt,
                              $note,
                              $org eq 'MMI'
                                 ?calc_mmi_glnum($c,
                                                 $person_id,
                                                 $public,
                                                 $py->for_what(),
                                                 $prog_glnum,
                                                )
                                 : $prog_glnum,
                        )
                 .  '~'
                 ;
        $tbl_py_desc .= <<"EOH";
<tr>
<td align=right>$amt</td>
<td>$for</td>
<td>$note</td>
</tr>
EOH
    }
    if (! $npayments || ! $total) {
        return;     # no payments for the current $org
    }
    my $comma_total = commify($total);
    $tbl_py_desc .= <<"EOH";
<tr>
<td style='border-top: solid thin' align=right>\$$comma_total</td>
</tr>
</table>
EOH
    #
    # create the file with Data::Dumper
    # and ftp it to the appropriate MMI/MMC site.
    #
    open my $out, '>', "/tmp/$code" or die "cannot create /tmp/$code: $!\n";
    my $user = $c->user->obj;
    my $signed = $user->first;
    my $quest_email = $user->email;
    print {$out} Dumper({
        py_desc  => $py_desc,
        first    => $person->first(),
        last     => $person->last(),
        addr     => $person->addr1() . " " . $person->addr2,
        city     => $person->city(),
        st_prov  => $person->st_prov(),
        zip_post => $person->zip_post(),
        country  => $person->country() || 'USA',
        email    => $email,
        phone    => $phone,
        total    => $total,
        py_desc  => $py_desc,
        tbl_py_desc => strip_nl($tbl_py_desc),
        program  => $program_name,
        code     => $code,
        reg_id   => $reg_id,
        person_id => $person_id,
        signed   => $signed,
        quest_email => $quest_email,
    });
    close $out;

    # and send it - we assume it will be sent properly
    eval {
        my $o = $org eq 'MMI'? 'mmi_': '';
            # ftp_site was first, then ftp_mmi_site
        my $ftp = Net::FTP->new($string{"ftp_${o}site"},
                                Passive => $string{"ftp_${o}passive"})
            or die qq!cannot connect to $string{"ftp_${o}site"}!;
        $ftp->login($string{"ftp_${o}login"}, $string{"ftp_${o}password"})
            or die "cannot login ", $ftp->message;
        # thanks to jnap and haarg
        # a nice HACK to force Extended Passive Mode:
        local *Net::FTP::pasv = \&Net::FTP::epsv;
        my $dir = $string{$org eq 'MMI'? 'req_mmi_dir': 'req_mmc_dir'};
        $ftp->cwd($dir) or die "cannot chdir to $dir";
        $ftp->ascii();
        $ftp->put("/tmp/$code", $code) or die "could not send /tmp/$code\n";
        if ($resend_all) {
            # delete any old code files
            for my $old_code (@old_codes) {
                $ftp->delete($old_code);
            }
        }
        $ftp->quit();
    };
    if ($@ && ! -e '/tmp/testing_req_payments') {
        # what to do???  it did not succeed.
        # how to notify the user?
        $c->log->info("failed to send payment: $@\n");
        $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
        return;
    }

    # mark the payment requests as sent - with the new code
    PAYMENT:
    for my $py ($reg->req_payments()) {
        next PAYMENT if $py->org() ne $org;
        next PAYMENT if !$resend_all && $py->code();
            # if not resending
            # $py->code means
            # already sent but not gotten yet
        $py->update({
            code => $code,
        });
    }

    unlink "/tmp/$code" unless -e '/tmp/testing_req_mmi';

    if ($no_email) {
        return $code;
    }
    #
    # send email to the person with the code
    #
    my $tt = Template->new({
        INCLUDE_PATH => 'root/static',
        EVAL_PERL    => 0,
        INTERPOLATE  => 1,
    });
    my $stash = {
        name        => $name,
        total       => $comma_total,
        req_code    => $code,
        tbl_py_desc => $tbl_py_desc,
        program     => $program_name,
        resending   => $resend_all,
        signed      => $signed,
        org         => $org eq 'MMC'? 'mountmadonna': 'mountmadonnainstitute',
    };
    my $html;
    $tt->process(
        "templates/letter/req_payment.tt2",   # template
        $stash,               # variables
        \$html,               # output
    ) or die "error in processing template: "
             . $tt->error();
    email_letter($c,
        to      => $email,
        from    => $user->first . ' ' . $user->last . ' '
                 . '<' . $user->email . '>',
        subject => "Requested Payment for Program '$program_name'",
        html    => $html,
    );
    # Reg History record
    my @who_now = get_now($c);
    model($c, 'RegHistory')->create({
        reg_id   => $reg_id,
        what     => ($resend_all? "REsent": "Sent")
                  . " $org requests totaling \$$comma_total",
        @who_now,
    });
    return $code;
}

sub delete_req : Local {
    my ($self, $c, $req_pay_id) = @_;
    my $req_pay = model($c, 'RequestedPayment')->find($req_pay_id);
    my $program_title = $req_pay->registration->program->title();
    my $person = $req_pay->registration->person;
    my $email = $person->email();
    my $reg_id = $req_pay->reg_id();
    my $tot = 0;
    my $word = '';
    if (my $code = $req_pay->code()) {
        # it was already sent
        for my $req (model($c, 'RequestedPayment')->search({
                         code => $code,
                     }))
        {
            $tot += $req->amount();
            $req->delete();
        }
        $tot = commify($tot);
        #
        # delete the code file on the mmi web site.
        # or maybe the MMC site???
        # req_mmi_dir vs req_mmc_dir
        my $ftp = Net::FTP->new($string{ftp_mmi_site},
                                Passive => $string{ftp_mmi_passive})
            or die "cannot connect to $string{ftp_mmi_site}";    # not die???
        # thanks to jnap and haarg
        # a nice HACK to force Extended Passive Mode:
        local *Net::FTP::pasv = \&Net::FTP::epsv;
        $ftp->login($string{ftp_mmi_login}, $string{ftp_mmi_password})
            or die "cannot login ", $ftp->message; # not die???
        $ftp->cwd($string{req_mmi_dir})
            or die "cannot chdir to $string{req_mmi_dir}";
        $ftp->delete($code);
        $ftp->quit();
        # 
        # send email notifying the person to ignore the request
        #
        my $tt = Template->new({
            INCLUDE_PATH => 'root/static',
            EVAL_PERL    => 0,
            INTERPOLATE  => 1,
        });
        my $stash = {
            name        => $person->name(),
            total       => $tot,
            program     => $program_title,
            signed      => $string{payment_request_signed},
        };
        my $html;
        $tt->process(
            "templates/letter/ignore_req_payment.tt2",   # template
            $stash,               # variables
            \$html,               # output
        ) or die "error in processing template: "
                 . $tt->error();
        email_letter($c,
            to      => $email,
            from    => $string{payment_request_from},
            subject => "Requested Payment for Program '$program_title'",
            html    => $html,
        );
        $word = 'totaling';
    }
    else {
        $tot = commify($req_pay->amount());
        $word = 'of';
        $req_pay->delete();
    }
    # Reg History record
    my @who_now = get_now($c);
    model($c, 'RegHistory')->create({
        reg_id   => $reg_id,
        what     => "Cancelled request $word \$$tot",
        @who_now,
    });
    $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
}

sub create_mmi_payment : Local {
    my ($self, $c, $reg_id, $person_id, $from, $amount) = @_;
    
    $amount ||= '';
    if (tt_today($c)->as_d8() eq get_string($c, 'last_mmi_deposit_date')) {
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
        amount   => $amount,
        for_what_opts => charges_and_payments_options(),
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
    my $reg = model($c, 'Registration')->find($reg_id);
    my $public = $reg->program->level->public();
    my $glnum = calc_mmi_glnum($c, $person_id, $public,
                               $for_what,
                               $reg->program->glnum());
    if ($glnum =~ m{XX}xms) {
        error($c,
            "The GL Number has not yet been assigned.",
            "registration/error.tt2",
        );
        return;
    }
    if ($glnum eq 'illegal') {
        $c->stash->{mess} = "The payment cannot be an Administrative or Clinic Fee.";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }
    my $the_date = tt_today($c)->as_d8();
    if ($the_date eq get_string($c, 'last_mmi_deposit_date')) {
        $the_date = (tt_today($c)+1)->as_d8();
    }
    my $payment = model($c, 'MMIPayment')->create({
        person_id => $person_id,
        amount    => $amount,
        type      => $c->request->params->{type},
        glnum     => $glnum,
        the_date  => $the_date,
        reg_id    => $reg_id,
        note      => $c->request->params->{note},
    });
    # Reg History record
    my @who_now = get_now($c);
    model($c, 'RegHistory')->create({
        reg_id => $reg_id,
        what   => "Payment of \$$amount for " . $payment->for_what(),
        @who_now,
    });
    $reg->calc_balance();
    if ($c->request->params->{from} 
        && $c->request->params->{from} eq 'edit_dollar')
    {
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
    for my $t (qw/ D C S O /) {
        $type_opts .= "<option value=$t"
                   .  ($type eq $t? " selected"
                      :             ""         )
                   .  ">"
                   .  $string{"payment_$t"}
                   .  "\n";
                   ;
    }
    my $for_what = substr($pay->glnum(), 0, 1);
    stash($c,
        from          => $from,
        type_opts     => $type_opts,
        for_what_opts => charges_and_payments_options($for_what),
        pay           => $pay,
        template      => 'person/update_mmi_payment.tt2',
    );
}

sub update_mmi_payment_do : Local {
    my ($self, $c, $pay_id) = @_;

    my $pay = model($c, 'MMIPayment')->find($pay_id);
    my $reg = $pay->registration();
    my $o_amount = $pay->amount();
    my $o_for_what = $pay->for_what();
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
    $reg->calc_balance();
    # add a RegHistory record
    my @who_now = get_now($c);
    model($c, 'RegHistory')->create({
        reg_id   => $pay->reg_id,
        what     => 'Updated Payment of '
                  . '$' . commify($o_amount) . " for $o_for_what"
                  . ' => '
                  . '$' . commify($amount)   . " for " . $pay->for_what . '.',
        @who_now,
    });
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
# no mailings at all
#
sub no_mailings : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Person')->find($id);
    $p->update({
        snail_mailings     => '',
        e_mailings         => '',
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

1;
