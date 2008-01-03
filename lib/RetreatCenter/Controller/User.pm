use strict;
use warnings;
package RetreatCenter::Controller::User;
use base 'Catalyst::Controller';

use Util qw/trim role_table/;

use lib '../../';       # so you can do a perl -c here.

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{users} = [
        $c->model('RetreatCenterDB::User')->search(
            undef,
            { order_by => 'username' }
        )
    ];
    $c->stash->{template} = "user/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    $c->model('RetreatCenterDB::User')->search({id => $id})->delete();
    $c->response->redirect($c->uri_for('/user/list'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $u = $c->stash->{user} = $c->model('RetreatCenterDB::User')->find($id);
    $c->stash->{role_table} = role_table($c, $u->roles());
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "user/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    my $user =  $c->model("RetreatCenterDB::User")->find($id);
    my %hash;
    for my $f (qw/
        username
        first
        last
        password
        email
    /) {
        $hash{$f} = $c->request->params->{$f};
    }
    $hash{email} = trim($hash{email});
    $user->update(\%hash);

    #
    # delete all old and add new roles
    #
    $c->model("RetreatCenterDB::UserRole")->search(
        { user_id => $id },
    )->delete();
    my @cur_roles = grep {  s{^role(\d+)}{$1}  }
                    keys %{$c->request->params};
    for my $r (@cur_roles) {
        $c->model("RetreatCenterDB::UserRole")->create({
            user_id => $id,
            role_id => $r,
        });
    }

    $c->response->redirect($c->uri_for("/user/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $u = $c->stash->{user}
        = $c->model("RetreatCenterDB::User")->find($id);
    $c->stash->{template} = "user/view.tt2";
}

sub create : Local {
    my ($self, $c, $user_id) = @_;

    $c->stash->{role_table}  = role_table($c);
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "user/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    my %hash;
    for my $f (qw/
        username
        first
        last
        password
        email
    /) {
        $hash{$f} = $c->request->params->{$f};
    }
    $hash{email} = trim($hash{email});
    my $u = $c->model("RetreatCenterDB::User")->create(\%hash);
    my $id = $u->id;

    # add roles
    my @cur_roles = grep {  s{^role(\d+)}{$1}  }
                    keys %{$c->request->params};
    for my $r (@cur_roles) {
        $c->model("RetreatCenterDB::UserRole")->create({
            user_id => $id,
            role_id => $r,
        });
    }

    $c->response->redirect($c->uri_for("/user/view/$id"));
}

sub pass : Local {
    my ($self, $c) = @_;

    $c->stash->{template} = "user/pass.tt2";
}

sub pass_do : Local {
    my ($self, $c) = @_;

    $c->log->info("user id is " . $c->user->id());
    my $good_pass = $c->user->password;
    my $cur_pass  = $c->request->params->{cur_pass};
    my $new_pass  = $c->request->params->{new_pass};
    my $new_pass2 = $c->request->params->{new_pass2};
    if ($good_pass ne $cur_pass) {
        $c->stash->{mess} = "Current password is not correct.";
    }
    elsif ($new_pass ne $new_pass2) {
        $c->stash->{mess} = "New passwords do not match.";
    }
    elsif (length($new_pass) < 5) {
        # what other restrictions?
        $c->stash->{mess} = "New password must be at least 5 characters.";
    }
    else {
        $c->user->update({
            password => $new_pass,
        });
        $c->stash->{mess} = "Password successfully changed.";
    }
    $c->stash->{template} = "gen_error.tt2";
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
