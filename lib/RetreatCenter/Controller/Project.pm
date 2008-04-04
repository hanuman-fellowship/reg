use strict;
use warnings;
package RetreatCenter::Controller::Project;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/empty model/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{projects} = [ model($c, 'Project')->search(
        undef,
        { order_by => 'descr' }
    ) ];
    $c->stash->{template} = "project/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    #
    # first, are there any donations to this project?
    # If so, show them and get confirmation before doing the deletion.
    #
    my $p = model($c, 'Project')->find($id);
    my @donations = $p->donations();

    if (@donations) {
        $c->stash->{project}    = $p;
        $c->stash->{donations}  = \@donations  if @donations;
        $c->stash->{template} = "project/del_confirm.tt2";
        return;
    }
    _del($c, $id);
    $c->response->redirect($c->uri_for('/project/list'));
}

sub del_confirm : Local {
    my ($self, $c, $id) = @_;

    if ($c->request->params->{yes}) {
        _del($c, $id);
    }
    $c->response->redirect($c->uri_for('/project/list'));
}

sub _del {
    my ($c, $id) = @_;

    model($c, 'Project')->search({id => $id})->delete();
    model($c, 'Donation')->search({project_id => $id})->delete();
}

sub update : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{project}       = model($c, 'Project')->find($id);
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "project/create_edit.tt2";
}

#
# check for dups???
#
sub update_do : Local {
    my ($self, $c, $id) = @_;

    my $descr = $c->request->params->{descr};
    if (empty($descr)) {
        $c->stash->{mess} = "Project description cannot be blank.";
        $c->stash->{template} = "project/error.tt2";
        return;
    }
    model($c, 'Project')->find($id)->update({
        descr => $descr,
    });
    $c->response->redirect($c->uri_for('/project/list'));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "project/create_edit.tt2";
}

#
# check for dups???
#
sub create_do : Local {
    my ($self, $c) = @_;

    my $descr = $c->request->params->{descr};
    if (empty($descr)) {
        $c->stash->{mess} = "Project description cannot be blank.";
        $c->stash->{template} = "project/error.tt2";
        return;
    }
    model($c, 'Project')->create({
        descr => $descr,
    });
    $c->response->redirect($c->uri_for('/project/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

sub donations : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{project} = model($c, 'Project')->find($id);
    $c->stash->{template} = "project/view.tt2";
}

1;
