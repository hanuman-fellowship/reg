use strict;
use warnings;
package RetreatCenter::Controller::Role;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/model/;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{roles} = [
        model($c, 'Role')->search(
            undef,
            { order_by => 'fullname' },
        )
    ];
    $c->stash->{template} = "role/list.tt2";
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $r = $c->stash->{role} = model($c, 'Role')->find($id);
    $c->stash->{template} = "role/view.tt2";
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
