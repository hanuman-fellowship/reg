use strict;
use warnings;
package RetreatCenter::Controller::Issue;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    empty
    model
    trim
/;
use Date::Simple qw/
    today
    date
/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{issues} = [ model($c, 'Issue')->search(
        { date_closed => '' },
        { order_by    => 'priority, date_entered' }
    ) ];
    $c->stash->{template} = "issue/list.tt2";
}

sub search : Local {
    my ($self, $c) = @_;

    $c->stash->{issues} = [ model($c, 'Issue')->search(
        {
            title => { 'like' => "%".trim($c->request->params->{pat})."%" },
            date_closed => '',
        },
        { order_by    => 'priority, date_entered' }
    ) ];
    $c->stash->{closed_issues} = [ model($c, 'Issue')->search(
        {
            title => { 'like' => "%".trim($c->request->params->{pat})."%" },
            date_closed => { '!=', '' },
        },
        { order_by    => 'priority, date_entered' }
    ) ];
    $c->stash->{template} = "issue/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    model($c, 'Issue')->search({id => $id})->delete();
    $c->response->redirect($c->uri_for('/issue/list'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{issue}       = model($c, 'Issue')->find($id);
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "issue/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    my %hash = %{ $c->request->params() };
    # verify what???
    my $dt = date($hash{date_closed});
    $hash{date_closed} = $dt? $dt->as_d8()
                         :    ""
                         ;
    model($c, 'Issue')->find($id)->update(\%hash);
    $c->response->redirect($c->uri_for('/issue/list'));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "issue/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    my %hash = %{ $c->request->params() };
    $hash{date_entered} = today()->as_d8();
    $hash{date_closed}  = '';
    $hash{user_id} = $c->user->obj->id();
    model($c, 'Issue')->create(\%hash);
    $c->response->redirect($c->uri_for('/issue/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
