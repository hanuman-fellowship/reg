use strict;
use warnings;
package RetreatCenter::Controller::Configuration;
use base 'Catalyst::Controller';

use Util qw/
    stash
/;

use Global;

sub index : Local {
    my ($self, $c) = @_;

    stash($c,
        pg_title => "Configuration",
        template => "configuration/index.tt2",
    );
}

#
# no longer needed???
# since we always do the Global->init($c, 1) after
# house/cluster mods?
#
sub reload : Local {
    my ($self, $c) = @_;

    Global->init($c, 1);
    $c->response->redirect($c->uri_for("/configuration"));
}

sub mark_inactive : Local {
    my ($self, $c) = @_;

    my ($date_last) = $c->request->params->{date_last};
    my $dt = date($date_last);
    if (! $dt) {
        $c->stash->{mess} = "Invalid date: $date_last";
        $c->stash->{template} = "listing/error.tt2";
        return;
    }
    my $dt8 = $dt->as_d8();
    my $n = model($c, 'Person')->search({
        inactive => '',
        date_updat => { "<=", $dt8 },
    })->count();
    $c->stash->{date_last} = $dt;
    $c->stash->{count} = $n;
    $c->stash->{template} = "listing/inactive.tt2";
}

sub mark_inactive_do : Local {
    my ($self, $c, $date_last) = @_;
}

sub help_upload : Local {
    my ($self, $c) = @_;

    if (my $upload = $c->request->upload('helpfile')) {
        my $name = $upload->filename;
        $name =~ s{.*/}{};
        $upload->copy_to("root/static/help/$name");
    }
    $c->response->redirect($c->uri_for("/static/help/index.html"));
}

1;
