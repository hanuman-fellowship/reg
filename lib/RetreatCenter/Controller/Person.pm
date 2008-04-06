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
/;
use Date::Simple qw/date today/;
use USState;
use LWP::Simple;

Date::Simple->default_format("%D");      # set it here - where else???

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
    my ($self, $c, $pattern, $field, $match, $nrecs) = @_;

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
        if (defined $field && ($field eq $f || $match eq $f)) {
            $c->stash->{"$f\_selected"} = "selected";
        }
    }
    $c->stash->{template} = "person/search.tt2";
}

sub search_do : Local {
    my ($self, $c) = @_;

    my $pattern = trim($c->request->params->{pattern});
    my $orig_pattern = $pattern;
    $pattern =~ s{\*}{%}g;
    # % in a web form messes with url encoding... :(
    # even when method=post?

    my $field   = $c->request->params->{field};
    my $match   = $c->request->params->{match};
    my $nrecs   = 15;
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
            tel_home => { like => "$pattern" },
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
        $c->response->redirect($c->uri_for("/person/search/$orig_pattern/$field/$match/$nrecs"));
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
                            . "&match=$match"
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
                            . "&match=$match"
                            . "&offset=" . ($offset+$nrecs);
    }
    $c->stash->{field} = $field eq 'tel_home'? 'tel_home': 'email';
    $c->stash->{people} = \@people;
    $c->stash->{template} = "person/search_result.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Person')->find($id);

    #
    # if this person is a leader or a member
    # they can't be deleted.  their leadership
    # and membership must be deleted first.
    # I could ask if they would like me to do
    # that for them but I don't feel like it at the moment.
    # it _should_ be hard to delete such people.
    #
    # what about registrations???  these, too.
    #
    if ($p->leader || $p->member) {
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
    my ($name) = @_;

    my $html = get("http://www.gpeters.com/names/baby-names.php?"
                  ."name=" . $name);
    my ($likelihood, $gender) =
        $html =~ m{popular usage, it is <b>([\d.]+).*?to be a (\w+)'s};
    my %name = qw(
        girl Female
        boy  Male
    );
    if ($gender) {
        return "$likelihood => $name{$gender}";
    }
    if (($gender) = $html =~ m{It's a (.*?)!}) {
        return "$name{$gender}";
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
    $c->stash->{person} = $p;
    my $sex = $p->sex();
    $c->stash->{sex} = ($sex eq "M")? "Male"
                      :($sex eq "F")? "Female"
                      :               "Not Reported";
    if ($sex ne 'M' && $sex ne 'F') {
            $c->stash->{sex} .= "<br>". _what_gender($p->first);
    }
    $c->stash->{affils} = [ $p->affils() ];
    $c->stash->{date_entrd} = date($p->date_entrd()) || "";
    $c->stash->{date_updat} = date($p->date_updat()) || "";

    # Schwartzian???
    # get the registrations and sort them
    # in reverse program start date order.   Is there
    # a way to do this within DBIx relationships?
    # perhaps.
    my @regs = sort {
                   $b->program->sdate cmp $a->program->sdate
               }
               $p->registrations;
    if (@regs) {
        $c->stash->{registrations} = \@regs;
    }

    $c->stash->{template} = "person/view.tt2";
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{e_mailings}     = "checked";
    $c->stash->{snail_mailings} = "checked";
    $c->stash->{share_mailings} = "checked";
    $c->stash->{ambiguous}   = "";
    $c->stash->{affil_table} = affil_table($c);
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "person/create_edit.tt2";
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    for my $k (keys %hash) {
        delete $hash{$k} if $k =~ m{^aff\d+$};
    }
    # since unchecked checkboxes are not sent...
    for my $f (qw/
        e_mailings
        snail_mailings
        share_mailings
        ambiguous
    /) {
        $hash{$f} = "" unless exists $hash{$f};
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
    if ($hash{sex} ne 'F' && $hash{sex} ne 'M') {
        push @mess, "You must specify Male or Female: $hash{first} - "
                  . _what_gender($hash{first});
    }
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
        # make sure they're marked ambiguous.
        for my $dup (@dups, $p) {
            $dup->update({
                ambiguous => "yes",
            });
        }
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
    my $dups;
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

    my $p = model($c, 'Person')->create({
        %hash,
        date_updat => today()->as_d8(),
        date_entrd => today()->as_d8(),
    });
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
    $c->stash->{person} = $p;
    my $sex = $p->sex();
    $c->stash->{sex_female}  = ($sex eq "F")? "checked": "";
    $c->stash->{sex_male}    = ($sex eq "M")? "checked": "";
    $c->stash->{e_mailings}     = (    $p->e_mailings())? "checked": "";
    $c->stash->{snail_mailings} = ($p->snail_mailings())? "checked": "";
    $c->stash->{share_mailings} = ($p->share_mailings())? "checked": "";
    $c->stash->{ambiguous}   = ($p->ambiguous())? "checked": "";
    $c->stash->{affil_table} = affil_table($c, $p->affils());
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "person/create_edit.tt2";
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
    $p->update({
        %hash,
        date_updat => today()->as_d8(),
    });
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
    my $pronoun = ($p->sex eq "M")? "his": "her";
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
        date_updat => today()->as_d8(),
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
                date_updat => today()->as_d8(),
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
                date_updat => today()->as_d8(),
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
        date_entrd => today()->as_d8(),
        date_updat => today()->as_d8(),
    });
    $p1->update({
        id_sps     => $p2->id,
        date_updat => today()->as_d8(),
    });
    my $pronoun = ($sex2 eq 'M')? "him": "her";
    $c->flash->{message} = "Created"
                         . " " . _view_person($p2)
                         . " and partnered $pronoun with"
                         . " " . _view_person($p1)
                         . ".";
    $c->response->redirect($c->uri_for("/person/search"));
}

# show all future programs and allow one to be chosen
sub register1 : Local {
    my ($self, $c, $id) = @_;

    my $person = model($c, 'Person')->find($id);
    my @programs = model($c, 'Program')->search(
        {
            sdate => { '>=',    today()->as_d8() },
            name  => { -not_like => '%personal%retreat%' },
        },
        { order_by => [ 'sdate', 'name' ] },
    );
    my $jan1 = date(today()->year(), 1, 1)->as_d8();
    my (@personal_retreats) = model($c, 'Program')->search(
        {
            name  => { like => '%personal%retreat%' },
            sdate => { '>=', $jan1 },
        },
        { order_by => 'sdate' },
    );
    unshift @programs, @personal_retreats;
    $c->stash->{person}   = $person;
    $c->stash->{programs} = \@programs;
    $c->stash->{template} = "person/register.tt2";
}

1;
