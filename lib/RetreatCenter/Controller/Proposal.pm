use strict;
use warnings;
package RetreatCenter::Controller::Proposal;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    model
    lines
    etrim
    tt_today
    nsquish
    empty
/;
use Date::Simple qw/
    date
/;

my @mess;
my %hash;
sub _get_data {
    my ($c) = @_;

    @mess = ();
    %hash = %{ $c->request->params() };
    for my $f (keys %hash) {
        $hash{$f} = etrim($hash{$f});
    }

    my $dt = date($hash{date_of_call});
    if (! $dt) {
        push @mess, "Invalid Date of Call: $hash{date_of_call}";
    }
    else {
        $hash{date_of_call} = $dt->as_d8();
    }
    $dt = date($hash{program_meeting_date});
    if (! $dt) {
        push @mess, "Invalid Program Meeting Date: $hash{program_meeting_date}";
    }
    else {
        $hash{program_meeting_date} = $dt->as_d8();
    }
    $hash{denied} = "" unless exists $hash{denied};
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "program/error.tt2";
    }
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "proposal/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    my $proposal = model($c, 'Proposal')->create(\%hash);
    my $id = $proposal->id();
    $c->response->redirect($c->uri_for("/proposal/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $proposal = model($c, 'Proposal')->find($id);
    $c->stash->{proposal} = $proposal;
    $c->stash->{template} = "proposal/view.tt2";
}

sub update : Local {
    my ($self, $c, $id) = @_;
 
    my $proposal = model($c, 'Proposal')->find($id);
    $c->stash->{proposal} = $proposal;
    for my $f (qw/
        special_needs
        food_service
        other_requests
        misc_notes
        provisos
    /) {
        $c->stash->{"$f\_rows"} = lines($proposal->$f()) + 3;    # 3 in strings?
    }
    for my $w (qw/ date_of_call program_meeting_date /) {
        $c->stash->{$w} = date($proposal->$w) || "";
    }
    $c->stash->{"check_denied"}  = ($proposal->denied())? "checked": "";
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template} = "proposal/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    my $proposal = model($c, 'Proposal')->find($id);
    _get_data($c);
    $proposal->update(\%hash);
    $c->response->redirect($c->uri_for("/proposal/view/$id"));
}

#
# show proposals 30 days after the
# date of the original call.
#
sub list : Local {
    my ($self, $c) = @_;

    Global->init($c);
    my $date_limit = (tt_today($c) - 30)->as_d8();
    $c->stash->{proposals} = [
        model($c, 'Proposal')->search(
            { date_of_call => { '>=', $date_limit } },
            { order_by     => 'date_of_call' },
        )
    ];
    $c->stash->{proposal_pat} = "";
    $c->stash->{template} = "proposal/list.tt2";
}

#
#
#
sub delete : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Proposal')->find($id);
    $p->delete();
    $c->response->redirect($c->uri_for('/proposal/list'));
}

#
# there's a pattern - use it to select the proposals to show.
#
sub listpat : Local {
    my ($self, $c) = @_;
    
    my $pat = $c->request->params->{proposal_pat};
    $c->stash->{proposals} = [
        model($c, 'Proposal')->search(
            { group_name => { 'like' => "%$pat%" }  },
            { order_by   => 'date_of_call' },
        )
    ];
    $c->stash->{proposal_pat} = $pat;
    $c->stash->{template} = "proposal/list.tt2";
}

sub approve : Local {
    my ($self, $c, $id) = @_;

    my $proposal = model($c, 'Proposal')->find($id);

    my $person_id = _transmit($c, $id);
    my $cs_person_id = 0;
    if (! empty($proposal->cs_last())) {
        $cs_person_id = _cs_transmit($c, $id);
    }
    # ??? if transmit fails...

    # now we fill in the stash in preparation for
    # the creation of a rental.  code copied from Rental->create().
    $c->stash->{check_linked}      = "";
    $c->stash->{check_tentative}   = "checked";
    $c->stash->{housecost_opts} =
        [ model($c, 'HouseCost')->search(
            undef,
            { order_by => 'name' },
        ) ];
    $c->stash->{rental} = {     # double faked object
        housecost => { name => "Default" },
        name           => $proposal->group_name(),
        coordinator_id => $person_id,
        cs_person_id   => $cs_person_id,
        max            => $proposal->max(),
        deposit        => $proposal->deposit(),
        start_hour     => $proposal->checkin_time(),
        end_hour       => $proposal->checkout_time(),
        # what else???
    };
    $c->stash->{section}     = 1;   # web
    $c->stash->{template}    = "rental/create_edit.tt2";
    $c->stash->{form_action} = "create_from_proposal/$id";
}

#
# move the person from proposal to person
# and put the person_id in the proposal.
#
sub transmit : Local {
    my ($self, $c, $id) = @_;

    _transmit($c, $id);
    $c->response->redirect($c->uri_for("/proposal/view/$id"));
}

sub _transmit {
    my ($c, $id) = @_;

    my $proposal = model($c, 'Proposal')->find($id);

    # first, find the id of the affiliation 'Proposal Submitter'
    my $prop_sub_id = 0;
    my @prop_sub = model($c, 'Affil')->search({
                       descrip => { 'like' => '%proposal%submitter%' },
                   });
    if (@prop_sub) {
        $prop_sub_id = $prop_sub[0]->id();
    }
    else {
        $c->stash->{mess}
            = "Sorry, you must first create a Proposal Submitter affiliation";
        $c->stash->{template} = "proposal/error.tt2";
        return;
    }

    # does this person already exist in the People table?
    my @people = model($c, 'Person')->search({
                     first => $proposal->first(),
                     last  => $proposal->last(),
                 });

    my $person_id;
    if (@people == 1) {
        my $person = $people[0];
        $person_id = $person->id();
        $person->update({
            addr1    => $proposal->addr1(),
            addr2    => $proposal->addr2(),
            city     => $proposal->city(),
            st_prov  => $proposal->st_prov(),
            zip_post => $proposal->zip_post(),
            country  => $proposal->country(),
            tel_home => $proposal->tel_home(),
            tel_work => $proposal->tel_work(),
            tel_cell => $proposal->tel_cell(),
            email    => $proposal->email(),
        });
        # did the above clobber anything important???
        # hope not.

        # if they don't already have the proposal submitter affil, add it.
        my @affils = model($c, 'AffilPerson')->search({
                         a_id => $prop_sub_id,
                         p_id => $person_id,
                     });
        if (! @affils) {
            model($c, 'AffilPerson')->create({
                a_id => $prop_sub_id,
                p_id => $person_id,
            });
        }

        # finally update the proposal
        $proposal->update({
            person_id => $person_id,
        });
    }
    elsif (! @people) {
        my $person = model($c, 'Person')->create({
            first    => $proposal->first(),
            last     => $proposal->last(),
            addr1    => $proposal->addr1(),
            addr2    => $proposal->addr2(),
            city     => $proposal->city(),
            st_prov  => $proposal->st_prov(),
            zip_post => $proposal->zip_post(),
            country  => $proposal->country(),
            tel_home => $proposal->tel_home(),
            tel_work => $proposal->tel_work(),
            tel_cell => $proposal->tel_cell(),
            email    => $proposal->email(),
            akey     => nsquish($proposal->addr1(),
                                $proposal->addr2(),
                                $proposal->zip_post()
                        ),
        });
        $person_id = $person->id();
        model($c, 'AffilPerson')->create({
            a_id => $prop_sub_id,
            p_id => $person_id,
        });
        $proposal->update({
            person_id => $person_id,
        });
    }
    else {
        # more than one match - damn
        # ???
    }
    return $person_id;
}

# ??? UGly to copy above.
# how else?   method name constructed by prepending "cs_"?
sub _cs_transmit {
    my ($c, $id) = @_;

    my $proposal = model($c, 'Proposal')->find($id);

    # does this person already exist in the People table?
    my @people = model($c, 'Person')->search({
                     first => $proposal->cs_first(),
                     last  => $proposal->cs_last(),
                 });

    my $person_id;
    if (@people == 1) {
        my $person = $people[0];
        $person_id = $person->id();
        $person->update({
            addr1    => $proposal->cs_addr1(),
            addr2    => $proposal->cs_addr2(),
            city     => $proposal->cs_city(),
            st_prov  => $proposal->cs_st_prov(),
            zip_post => $proposal->cs_zip_post(),
            country  => $proposal->cs_country(),
            tel_home => $proposal->cs_tel_home(),
            tel_work => $proposal->cs_tel_work(),
            tel_cell => $proposal->cs_tel_cell(),
            email    => $proposal->cs_email(),
        });
        # did the above clobber anything important???
        # hope not.

        # update the proposal
        $proposal->update({
            cs_person_id => $person_id,
        });
    }
    elsif (! @people) {
        my $person = model($c, 'Person')->create({
            first    => $proposal->cs_first(),
            last     => $proposal->cs_last(),
            addr1    => $proposal->cs_addr1(),
            addr2    => $proposal->cs_addr2(),
            city     => $proposal->cs_city(),
            st_prov  => $proposal->cs_st_prov(),
            zip_post => $proposal->cs_zip_post(),
            country  => $proposal->cs_country(),
            tel_home => $proposal->cs_tel_home(),
            tel_work => $proposal->cs_tel_work(),
            tel_cell => $proposal->cs_tel_cell(),
            email    => $proposal->cs_email(),
            akey     => nsquish($proposal->cs_addr1(),
                                $proposal->cs_addr2(),
                                $proposal->cs_zip_post()
                        ),
        });
        $person_id = $person->id();
        $proposal->update({
            cs_person_id => $person_id,
        });
    }
    else {
        # more than one match - damn
        # ???
    }
    return $person_id;
}

1;
