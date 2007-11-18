use strict;
use warnings;

package RetreatCenter::Controller::Affil;
use base 'Catalyst::Controller';

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{affil} = [ $c->model('RetreatCenterDB::Affil')->search(
        undef,
        { order_by => 'descrip' }
    ) ];
    $c->stash->{template} = "affil/list.tt2";
}

# ??? confirm deletion and supply a count
# of how many people and reports are affected.
# also cascade deletes to report_afill as well
sub delete : Local {
    my ($self, $c, $id) = @_;

    #$c->model('RetreatCenterDB::Affil')->find($id)->delete();
    # this will delete others in affil_people?
    # yes but very very inefficiently. :(
    # better:
    $c->model('RetreatCenterDB::Affil')->search({id => $id})->delete();
    $c->model('RetreatCenterDB::AffilPerson')->search({a_id => $id})->delete();
    $c->response->redirect($c->uri_for('/affil/list'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{affil}       = $c->model('RetreatCenterDB::Affil')->find($id);
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "affil/affil.tt2";
}

#
# currently there's no way to know which fields changed
# so assume they all did.
#
# check for dups???
#
sub update_do : Local {
    my ($self, $c, $id) = @_;

    $c->model("RetreatCenterDB::Affil")->find($id)->update({
        descrip => $c->request->params->{descrip},
    });
    $c->response->redirect($c->uri_for('/affil/list'));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "affil/affil.tt2";
}

#
# check for dups???
#
sub create_do : Local {
    my ($self, $c) = @_;

    $c->model("RetreatCenterDB::Affil")->create({
        descrip => $c->request->params->{descrip},
    });
    $c->response->redirect($c->uri_for('/affil/list'));
}

1;
