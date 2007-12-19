use strict;
use warnings;
package RetreatCenter::Controller::Leader;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{leaders} = [
        # how to sort like this in all()???
        sort {
            $a->person->last()  cmp $b->person->last()
            or
            $a->person->first() cmp $b->person->first()
        }
        $c->model('RetreatCenterDB::Leader')->all()
    ];
    $c->stash->{template} = "leader/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    $c->model('RetreatCenterDB::Leader')->search({id => $id})->delete();
    $c->response->redirect($c->uri_for('/leader/list'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $l = $c->stash->{leader} = 
        $c->model('RetreatCenterDB::Leader')->find($id);
    $c->stash->{person} = $l->person();
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "leader/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    $c->model("RetreatCenterDB::Leader")->find($id)->update({
        public_email => $c->request->params->{public_email},
        image        => $c->request->params->{image},
        url          => $c->request->params->{url},
        biography    => $c->request->params->{biography},
    });
    $c->response->redirect($c->uri_for('/leader/list'));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $l = $c->stash->{leader}
        = $c->model("RetreatCenterDB::Leader")->find($id);
    my $bio = $l->biography();
    $bio =~ s{\r?\n}{<br>\n}g if $bio;
    $c->stash->{biography} = $bio;
    $c->stash->{template} = "leader/view.tt2";
}

sub create : Local {
    my ($self, $c, $person_id) = @_;

    $c->stash->{person}
        = $c->model("RetreatCenterDB::Person")->find($person_id);
    $c->stash->{form_action} = "create_do/$person_id";
    $c->stash->{template}    = "leader/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c, $person_id) = @_;

    $c->model("RetreatCenterDB::Leader")->create({
        person_id    => $person_id,
        public_email => $c->request->params->{public_email},
        image        => $c->request->params->{image},
        url          => $c->request->params->{url},
        biography    => $c->request->params->{biography},
    });
    $c->response->redirect($c->uri_for('/leader/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
