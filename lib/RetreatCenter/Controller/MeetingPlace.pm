use strict;
use warnings;
package RetreatCenter::Controller::MeetingPlace;
use base 'Catalyst::Controller';

use Date::Simple qw/
    date
/;
use Util qw/
    trim
    empty
    model
    stash
    d3_to_hex
/;

use lib '../../';       # so you can do a perl -c here.

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub create : Local {
    my ($self, $c) = @_;

    stash($c,
        red             => 127,
        green           => 127,
        blue            => 127,
        check_sleep_too => '',
        form_action     => "create_do",
        template        => "meetingplace/create_edit.tt2",
    );
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    $hash{$_} =~ s{^\s*|\s*$}{}g for keys %hash;
    if (! exists $hash{sleep_too}) {
        $hash{sleep_too} = '';
    }
    @mess = ();
    for my $f (qw/abbr name disp_ord color/) {
        if (empty($hash{$f})) {
            push @mess, "\u$f cannot be blank";
        }
    }
    if (! @mess) {
        if (! $hash{max} =~ m{^\d+$}) {
            push @mess, "Illegal maximum: $hash{max}";
        }
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "meetingplace/error.tt2";
    }
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;

    my $meetingplace = model($c, 'MeetingPlace')->create(\%hash);
    my $id = $meetingplace->id();
    $c->response->redirect($c->uri_for("/meetingplace/list"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $mp = model($c, 'MeetingPlace')->find($id);
    $mp->{bgcolor} = d3_to_hex($mp->color);
    $c->stash->{mp} = $mp;
    $c->stash->{template}     = "meetingplace/view.tt2";
}

sub list : Local {
    my ($self, $c) = @_;

    my @mp = model($c, 'MeetingPlace')->search(
                 undef,
                 { order_by => 'abbr' },
             );
    for my $mp (@mp) {
        $mp->{bgcolor} = d3_to_hex($mp->color);
    }
    stash(
        pg_title      => "Meeting Places",
        meetingplaces => \@mp,
        template      => "meetingplace/list.tt2",
    );
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $mp = model($c, 'MeetingPlace')->find($id);
    my ($r, $g, $b) = $mp->color =~ m{\d+}g;
    stash($c,
        meetingplace    => $mp,
        red             => $r,
        green           => $g,
        blue            => $b,
        check_sleep_too => ($mp->sleep_too()? "checked": ""),
        form_action     => "update_do/$id",
        template        => "meetingplace/create_edit.tt2",
    );
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    model($c, 'MeetingPlace')->find($id)->update(\%hash);
    $c->response->redirect($c->uri_for("/meetingplace/list"));
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    model($c, 'MeetingPlace')->find($id)->delete();
    $c->response->redirect($c->uri_for('/meetingplace/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
