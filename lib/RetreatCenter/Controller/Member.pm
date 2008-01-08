use strict;
use warnings;
package RetreatCenter::Controller::Member;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/trim/;
use Date::Simple qw/date today/;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    #
    # before getting the list, look for lapsed people.
    #
    my $today = today()->as_d8();
    $c->model('RetreatCenterDB::Member')->search({
        category     => 'General',
        date_general => { '<' => $today },
    })->update({
        category    => 'Lapsed',
        date_lapsed => $today,
    });
    my $month3 = (today()-90)->as_d8();     # 3 months ago for Sponsors
    $c->model('RetreatCenterDB::Member')->search({
        category     => 'Sponsor',
        date_sponsor => { '<' => $month3 },
    })->update({
        category    => 'Lapsed',
        date_lapsed => $today,
    });
    my @members =
        map {
            $_->[1]
        }
        sort {
            $a->[0] cmp $b->[0]
        }
        map {
            [ $_->person->sanskrit || $_->person->first, $_ ]
        }
        $c->model('RetreatCenterDB::Member')->all();
    for my $m (@members) {
        my $c = lc $m->category;
        my $method = "date_$c";
        $m->{$c} = date($m->$method);
    }
    $c->stash->{members} = \@members;
    $c->stash->{template} = "member/list.tt2";
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $m = $c->stash->{member} = 
        $c->model('RetreatCenterDB::Member')->find($id);
    for my $w (qw/
        general
        sponsor
        life
        lapsed
    /) {
        my $method = "date_$w";
        $c->stash->{"date_$w"} = date($m->$method) || "";
        $c->stash->{"category_$w"} = ($m->category eq ucfirst($w))? "checked": "";
    }
    $c->stash->{person} = $m->person();
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "member/create_edit.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    $c->model('RetreatCenterDB::Member')->search({id => $id})->delete();
    $c->response->redirect($c->uri_for('/member/list'));
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    # dates are either blank or converted to d8 format
    my @mess;
    for my $d (qw/
        date_general
        date_sponsor
        date_life
        date_lapsed
    /) {
        my $fld = $c->request->params->{$d};
        my $dt = date($fld);
        if ($fld && ! $dt) {
            # tell them which date field is wrong???
            push @mess, "Invalid date: $fld";
            next;
        }
        $c->request->params->{$d} = $dt? $dt->as_d8()
                                   :     "";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "program/error.tt2";
        return;
    }

    my %hash;
    for my $w (qw/
        category
        date_general
        date_sponsor
        date_life
        date_lapsed
        total_paid
    /) {
        $hash{$w} = $c->request->params->{$w};
    }
    my $member =  $c->model("RetreatCenterDB::Member")->find($id);
    $member->update({
        %hash,
    });
    # the person_id will not change here...
    $c->response->redirect($c->uri_for("/member/list"));
}

sub create : Local {
    my ($self, $c, $person_id) = @_;

    $c->stash->{person}
        = $c->model("RetreatCenterDB::Person")->find($person_id);
    $c->stash->{form_action} = "create_do/$person_id";
    $c->stash->{template}    = "member/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c, $person_id) = @_;

    # dates are either blank or converted to d8 format
    my @mess;
    for my $d (qw/
        date_general
        date_sponsor
        date_life
        date_lapsed
    /) {
        my $fld = $c->request->params->{$d};
        my $dt = date($fld);
        if ($fld && ! $dt) {
            # tell them which date field is wrong???
            push @mess, "Invalid date: $fld";
            next;
        }
        $c->request->params->{$d} = $dt? $dt->as_d8()
                                   :     "";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "program/error.tt2";
        return;
    }

    my %hash;
    for my $w (qw/
        category
        date_general
        date_sponsor
        date_life
        date_lapsed
        total_paid
    /) {
        $hash{$w} = $c->request->params->{$w};
    }
    my $m = $c->model("RetreatCenterDB::Member")->create({
        person_id    => $person_id,
        %hash,
    });
    my $id = $m->id();      # the new member id
    $c->response->redirect($c->uri_for("/member/list"));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
