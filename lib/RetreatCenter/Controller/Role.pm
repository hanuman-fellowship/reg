use strict;
use warnings;
package RetreatCenter::Controller::Role;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    model
    stash
    read_only
/;

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

# needed by ACL???
sub view : Local {
    my ($self, $c, $id) = @_;
    $c->forward('update');
}

sub update : Local {
    my ($self, $c, $role_id) = @_;

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    my $role = model($c, 'Role')->find($role_id);
    stash($c,
        role     => $role,
        template => "role/update.tt2",
    );
}

sub update_do : Local {
    my ($self, $c, $role_id) = @_;

    # delete all old roles and create the new ones.
    model($c, 'UserRole')->search(
        { role_id => $role_id },
    )->delete();
    my @user_ids = grep { s/^r(\d+)/$1/ }
                   $c->request->param;
    for my $user_id (@user_ids) {
        model($c, 'UserRole')->create({
            user_id => $user_id,
            role_id => $role_id,
        });
    }
    $c->forward('list');
}

sub access_denied : Private {
    my ($self, $c) = @_;

    stash($c,
        mess     => "Authorization denied!",
        template => "gen_error.tt2",
    );
}

1;
