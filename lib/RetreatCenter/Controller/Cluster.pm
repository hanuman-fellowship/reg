use strict;
use warnings;
package RetreatCenter::Controller::Cluster;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    empty
    model
    trim
/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{clusters} = [ model($c, 'Cluster')->search(
        undef,
        { order_by => 'name' }
    ) ];
    $c->stash->{template} = "cluster/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    # cascade???
    model($c, 'Cluster')->find($id)->delete();
    $c->response->redirect($c->uri_for('/cluster/list'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $cl = $c->stash->{cluster}       = model($c, 'Cluster')->find($id);
    my ($r, $g, $b) = $cl->color =~ m{\d+}g;
    $c->stash->{red  } = $r;
    $c->stash->{green} = $g;
    $c->stash->{blue } = $b;
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "cluster/create_edit.tt2";
}

#
# currently there's no way to know which fields changed
# so assume they all did.
#
# check for dups???
#
sub update_do : Local {
    my ($self, $c, $id) = @_;

    my $name  = $c->request->params->{name};
    my $color = $c->request->params->{color};
    for my $f (qw/name color/) {
        if (empty($f)) {
            $c->stash->{mess} = "\u$f cannot be blank.";
            $c->stash->{template} = "cluster/error.tt2";
            return;
        }
    }
    my %coord = (x => "",  y => "");
    for my $f (qw/x y/) {
        my $fld = $c->request->params->{$f};
        if ($fld !~ m{^\s*\d*\s*$}) {
            $c->stash->{mess} = "\u$f Coord must be integral.";
            $c->stash->{template} = "cluster/error.tt2";
            return;
        }
        $coord{$f} = trim($fld);
    }
    model($c, 'Cluster')->find($id)->update({
        name  => $name,
        color => $color,
        x     => $coord{x},
        y     => $coord{y},
    });
    $c->response->redirect($c->uri_for('/cluster/list'));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{red  } = 255;
    $c->stash->{green} = 255;
    $c->stash->{blue } = 255;
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "cluster/create_edit.tt2";
}

#
# check for dups???
#
sub create_do : Local {
    my ($self, $c) = @_;

    my $name  = $c->request->params->{name};
    my $color = $c->request->params->{color};
    for my $f (qw/name color/) {
        if (empty($f)) {
            $c->stash->{mess} = "\u$f cannot be blank.";
            $c->stash->{template} = "cluster/error.tt2";
            return;
        }
    }
    my %coord = (x => "",  y => "");
    for my $f (qw/x y/) {
        my $fld = $c->request->params->{$f};
        if ($fld !~ m{^\s*\d*\s*$}) {
            $c->stash->{mess} = "\u$f Coord must be integral.";
            $c->stash->{template} = "cluster/error.tt2";
            return;
        }
        $coord{$f} = trim($fld);
    }
    model($c, 'Cluster')->create({
        name  => $name,
        color => $color,
        x     => $coord{x},
        y     => $coord{y},
    });
    $c->response->redirect($c->uri_for('/cluster/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
