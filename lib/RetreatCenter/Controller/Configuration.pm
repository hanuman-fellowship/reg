use strict;
use warnings;
package RetreatCenter::Controller::Configuration;
use base 'Catalyst::Controller';

use Util qw/
    stash
    model
/;

use Global;
use File::stat;

sub index : Local {
    my ($self, $c) = @_;

    stash($c,
        switch   => -f "$ENV{HOME}/Reg/INACTIVE",
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
        stash($c,
            mess     => "Invalid date: $date_last",
            template => 'listing/error.tt2',
        );
        return;
    }
    my $dt8 = $dt->as_d8();
    my $n = model($c, 'Person')->search({
        inactive => '',
        date_updat => { "<=", $dt8 },
    })->count();
    stash($c,
        date_last => $dt,
        count     => $n,
        template  => 'listing/inactive.tt2',
    );
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

sub switch : Local {
    my ($self, $c) = @_;

    stash($c,
        template => 'configuration/switch.tt2',
    );
}

sub switch_do : Local {
    my ($self, $c) = @_;

    unlink "$ENV{HOME}/Reg/INACTIVE";
    my $sb = stat("$ENV{HOME}/Reg/latest_synch");
    stash($c,
        latest   => scalar localtime $sb->mtime,
        template => 'configuration/switch_done.tt2',
    );
}

sub counts : Local {
    my ($self, $c) = @_;

    my @classes = map {
                      +{
                          name  => $_,
                          count => scalar(model($c, $_)->search),   # gives count?
                      }
                  }
                  sort
                  @{RetreatCenterDB->classes()};
    stash($c,
        classes  => \@classes,
        template => 'configuration/counts.tt2',
    );
}

1;
