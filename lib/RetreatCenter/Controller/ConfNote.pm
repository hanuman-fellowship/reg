use strict;
use warnings;

package RetreatCenter::Controller::ConfNote;
use base 'Catalyst::Controller';
use Util qw/
    model
    _br
/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{confnotes} = [
        model($c, 'ConfNote')->search(
            undef,
            { order_by => 'abbr' },
        )
    ];
    $c->stash->{template} = "confnote/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    model($c, 'ConfNote')->find($id)->delete();
    $c->response->redirect($c->uri_for('/confnote/list'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{confnote}    = model($c, 'ConfNote')->find($id);
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "confnote/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    # check abbr, expansion not empty???
    model($c, 'ConfNote')->find($id)->update({
        abbr      => $c->request->params->{abbr},
        expansion => $c->request->params->{expansion},
    });
    $c->response->redirect($c->uri_for('/confnote/list'));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "confnote/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    model($c, 'ConfNote')->create({
        abbr      => $c->request->params->{abbr},
        expansion => $c->request->params->{expansion},
    });
    $c->response->redirect($c->uri_for('/confnote/list'));
}

# ??? need to put this in place?
sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
