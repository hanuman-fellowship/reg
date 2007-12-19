use strict;
use warnings;
package RetreatCenter::Controller::HouseCost;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{housecosts} = [
        $c->model('RetreatCenterDB::HouseCost')->search(
            undef,
            {
                order_by => 'name',
            },
        )
    ];
    $c->stash->{template} = "housecost/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    $c->model('RetreatCenterDB::HouseCost')->search({id => $id})->delete();
    $c->response->redirect($c->uri_for('/housecost/list'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $hc = $c->stash->{housecost} = 
        $c->model('RetreatCenterDB::HouseCost')->find($id);
    my $type = $hc->type();
    $c->stash->{checked_perday} = ($type eq "Perday")? "checked": "";
    $c->stash->{checked_total}  = ($type eq "Total" )? "checked": "";
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "housecost/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    my %hash;
    # some way to ask DBIx for this list???
    # it knows
    for my $w (qw/
        name
        single
        double
        triple
        quad
        dormitory
        economy
        center_tent
        own_tent
        own_van
        commuting
        unknown
        single_bath
        double_bath
        type
    /) {
        $hash{$w} = $c->request->params->{$w};
    }
    $c->model("RetreatCenterDB::HouseCost")->find($id)->update({
        %hash,
    });
    $c->response->redirect($c->uri_for('/housecost/list'));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{housecost}
        = $c->model("RetreatCenterDB::HouseCost")->find($id);
    $c->stash->{template} = "housecost/view.tt2";
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{checked_perday} = "";
    $c->stash->{checked_total}  = "checked";
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "housecost/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    my %hash;
    # some way to ask DBIx for this list???
    # it knows
    for my $w (qw/
        name
        single
        double
        triple
        quad
        dormitory
        economy
        center_tent
        own_tent
        own_van
        commuting
        unknown
        single_bath
        double_bath
        type
    /) {
        $hash{$w} = $c->request->params->{$w};
    }
    $c->model("RetreatCenterDB::HouseCost")->create({
        %hash,
    });
    $c->response->redirect($c->uri_for('/housecost/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
