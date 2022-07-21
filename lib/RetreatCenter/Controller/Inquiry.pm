use strict;
use warnings;
package RetreatCenter::Controller::Inquiry;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    model
    stash
/;
use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{inquiries} = [ model($c, 'Inquiry')->search(
        undef,
        { order_by => 'the_date desc, the_time desc' }
    ) ];
    $c->stash->{template} = "inquiry/list.tt2";
}

sub view : Local {
    my ($self, $c, $inq_id) = @_;
    my $inq = model($c, 'Inquiry')->find($inq_id);
    my $notes = $inq->notes();
    #$notes =~ s{\n}{<br>\n}xmsg;
    stash($c,
        inquiry  => $inq,
        notes    => $notes,
        template => 'inquiry/view.tt2',
    );
}

sub notes : Local {
    my ($self, $c, $inq_id) = @_;
    my $inq = model($c, 'Inquiry')->find($inq_id);
    my $nrows = ($inq->notes() =~ tr/\n//);
    stash($c,
        inquiry  => $inq,
        nrows    => $nrows + 3,
        template => 'inquiry/notes_view.tt2',
    );
}

sub notes_do : Local {
    my ($self, $c, $inq_id) = @_;
    my $inq = model($c, 'Inquiry')->find($inq_id);
    $inq->update({
        notes => $c->request->params->{notes},
    });
    $c->response->redirect($c->uri_for("/inquiry/view/$inq_id"));
}

sub change_status : Local {
    my ($self, $c, $inq_id) = @_;
    my $inq = model($c, 'Inquiry')->find($inq_id);
    my @statuses = $inq->statuses(); 
    my $status_opts = '';
    for my $i (0 .. $#statuses) {
        my $selected = $i eq $inq->status? ' selected': '';
        $status_opts .= "<option value=$i$selected>$statuses[$i]</option>\n";
    }
    stash($c,
        inquiry  => $inq,
        status_opts => $status_opts,
        template => 'inquiry/change_status_view.tt2',
    );
}

sub change_status_do : Local {
    my ($self, $c, $inq_id) = @_;
    my $inq = model($c, 'Inquiry')->find($inq_id);
    $inq->update({
        status => $c->request->params->{new_status},
    });
    $c->response->redirect($c->uri_for("/inquiry/view/$inq_id"));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
