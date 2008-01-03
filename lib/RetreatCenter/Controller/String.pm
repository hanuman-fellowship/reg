use strict;
use warnings;

package RetreatCenter::Controller::String;
use base 'Catalyst::Controller';

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{strings} = [ $c->model('RetreatCenterDB::String')->search(
        undef,
        { order_by => 'key' }
    ) ];
    $c->stash->{template} = "string/list.tt2";
}

use URI::Escape;
sub update : Local {
    my ($self, $c, $key) = @_;

    my $s = $c->model('RetreatCenterDB::String')->find($key);

    $c->stash->{key} = $key;
    $c->stash->{value} = uri_escape($s->value, '"');
    $c->stash->{form_action} = "update_do/$key";
    $c->stash->{template}    = "string/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $key) = @_;

    $c->model("RetreatCenterDB::String")->find($key)->update({
        value => uri_unescape($c->request->params->{value}),
    });
    $c->response->redirect($c->uri_for('/string/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
