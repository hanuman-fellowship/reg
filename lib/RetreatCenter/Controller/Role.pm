use strict;
use warnings;
package RetreatCenter::Controller::Role;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{roles} = [
        $c->model('RetreatCenterDB::Role')->search(
            undef,
            { order_by => 'fullname' },
        )
    ];
    $c->stash->{template} = "role/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    $c->model('RetreatCenterDB::Role')->search({id => $id})->delete();
    $c->response->redirect($c->uri_for('/role/list'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $r = $c->stash->{role} = 
        $c->model('RetreatCenterDB::Role')->find($id);
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "role/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    $c->model("RetreatCenterDB::Role")->find($id)->update({
        role     => $c->request->params->{role},
        fullname => $c->request->params->{fullname},
        desc     => $c->request->params->{desc},
    });
    $c->response->redirect($c->uri_for("/role/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $r = $c->stash->{role}
        = $c->model("RetreatCenterDB::Role")->find($id);
    my $desc = $r->desc();
    $desc =~ s{\r?\n}{<br>\n}g if $desc;
    $c->stash->{desc} = $desc;
    $c->stash->{template} = "role/view.tt2";
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "role/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    my $r = $c->model("RetreatCenterDB::Role")->create({
        role     => $c->request->params->{role},
        fullname => $c->request->params->{fullname},
        desc     => $c->request->params->{desc},
    });
    my $id = $r->id();      # the new role id
    $c->response->redirect($c->uri_for("/role/view/$id"));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
