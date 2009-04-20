use strict;
use warnings;
package RetreatCenter::Controller::Issue;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    empty
    model
    trim
    email_letter
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

    my $pat = trim($c->request->params->{pat});
    if ($pat =~ m{^\d+}) {
        # they want a particular issue and have put the id
        # in the Search pattern field.
        __PACKAGE__->update($c, $pat);
        return;
    }
    if ($pat eq 'my') {
        my $uid = $c->user->obj->id();
        $c->stash->{issues} = [ model($c, 'Issue')->search(
            {
                user_id     => $uid,
                date_closed => '',
            },
            { order_by    => 'priority, date_entered' }
        ) ];
        $c->stash->{closed_issues} = [ model($c, 'Issue')->search(
            {
                user_id     => $uid,
                date_closed => { '!=', '' },
            },
            { order_by    => 'priority, date_entered' }
        ) ];
    }
    else {
        $c->stash->{issues} = [ model($c, 'Issue')->search(
            {
                title => { 'like' => "%$pat%" },
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
    }
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

    # be careful with the date closed param
    # for some reason if we put an undefined value
    # into sqlite it can't see it and it doesn't compare equal to ''.
    if ($hash{date_closed}) {
        my $dt = date($hash{date_closed});
        if ($dt) {
            $hash{date_closed} = $dt->as_d8();
        }
        else {
            delete $hash{date_closed};
            $hash{date_closed} = '';
        }
    }
    else {
        $hash{date_closed} = '';
    }

    my $issue = model($c, 'Issue')->find($id);
    $issue->update(\%hash);
    if ($hash{date_closed}) {
        # send email to the submitter
        my $submitter = $issue->user();
        my $user = $c->user->obj();
        email_letter($c,
            to      => $submitter->first() . " " . $submitter->last()
                     . "<" . $submitter->email() . ">",
            from    => $user->first() . " " . $user->last()
                     . "<" . $user->email() . ">",
            subject => "Issue #" . $issue->id() . " - " . $issue->title(),
            html    => $issue->notes()
                     . "<p><hr><p>This issue has been closed."
                     . "<p>See it <a href='" 
                     . $c->uri_for('/issue/update/' . $issue->id())
                     . "'>here</a>."
                     . "<p>Please verify that the issue actually <i>is</i> resolved."
        );
    }
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
    my $user = $c->user->obj();
    $hash{user_id} = $user->id();

    my $issue = model($c, 'Issue')->create(\%hash);

    my (@roles) = model($c, "Role")->search({
        role => 'developer',
    });
    # should just be one role

    email_letter($c,
        to      => join(', ', map { $_->email() } $roles[0]->users()),
        from    => $user->first() . " " . $user->last()
                 . '<' . $user->email() . '>',
        subject => "Issue #" . $issue->id() . " - " . $issue->title(),
        html    => $issue->notes()
                 . "<p><hr><p>See it <a href='" 
                 . $c->uri_for('/issue/update/' . $issue->id())
                 . "'>here</a>."
    );

    $c->response->redirect($c->uri_for('/issue/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
