use strict;
use warnings;
package RetreatCenter::Controller::CanPol;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{canpols} = [
        $c->model('RetreatCenterDB::CanPol')->search(
            undef,
            {
                order_by => 'name',
            },
        )
    ];
    $c->stash->{template} = "canpol/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    $c->model('RetreatCenterDB::CanPol')->search({id => $id})->delete();
    $c->response->redirect($c->uri_for('/canpol/list'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{canpol}       = $c->model('RetreatCenterDB::CanPol')->find($id);
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "canpol/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    $c->model("RetreatCenterDB::CanPol")->find($id)->update({
        name   => $c->request->params->{name},
        policy => $c->request->params->{policy},
    });
    $c->response->redirect($c->uri_for('/canpol/list'));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "canpol/create_edit.tt2";
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $cp = $c->stash->{canpol} =
        $c->model("RetreatCenterDB::CanPol")->find($id);
    my $s = $cp->policy();
    $s =~ s{\r?\n}{<br>\n}g;
    $c->stash->{policy} = $s;
    $c->stash->{template} = "canpol/view.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    $c->model("RetreatCenterDB::CanPol")->create({
        name   => $c->request->params->{name},
        policy => $c->request->params->{policy},
    });
    $c->response->redirect($c->uri_for('/canpol/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
