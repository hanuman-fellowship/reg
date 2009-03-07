use strict;
use warnings;
package RetreatCenter::Controller::User;
use base 'Catalyst::Controller';

use Util qw/
    trim
    empty
    role_table
    valid_email
    model
/;
use Global qw/
    %string
/;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{users} = [
        model($c, 'User')->search(
            undef,
            { order_by => 'username' }
        )
    ];
    $c->stash->{template} = "user/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    model($c, 'User')->search({id => $id})->delete();
    model($c, 'UserRole')->search(
        { user_id => $id }
    )->delete();
    $c->response->redirect($c->uri_for('/user/list'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $u = $c->stash->{user} = model($c, 'User')->find($id);
    $c->stash->{role_table} = role_table($c, $u->roles());
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "user/create_edit.tt2";
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{$c->request->params};
    for my $k (keys %hash) {
        if ($k =~ m{role\d+}) {
            delete $hash{$k};
        }
    }
    @mess = ();
    for my $k (keys %hash) {
        $hash{$k} = trim($hash{$k});
        if (empty($hash{$k})) {
            push @mess, "\u$k cannot be blank.";
        }
    }
    check_password($hash{password});
    if ($hash{email} && ! valid_email($hash{email})) {
        push @mess, "Invalid email: $hash{email}";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "user/error.tt2";
    }
}

sub check_password {
    my ($pass) = @_;

    my $lev = $string{password_security};
    if ($lev == 1) {
        if (length($pass) < 4) {
            push @mess, "Password must be at least 4 characters long.";
        }
        if ($pass =~ m{^[a-z]+$}) {
            push @mess, "Password cannot be all lower case letters.";
        }
    }
    elsif ($lev == 2) {
        if (length($pass) < 6) {
            push @mess, "Password must be at least 6 characters long.";
        }
        if (! (   $pass =~ m{[a-z]}
               && $pass =~ m{[A-Z]}
               && $pass =~ m{[0-9]}
               && $pass =~ m{\W}
        )) {
            push @mess, "Password must contain a lower case letter, an upper case letter, a digit, and a punctuation character.";
        }
    }
    # otherwise no restrictions
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    my $user =  model($c, 'User')->find($id);
    $user->update(\%hash);

    #
    # delete all old and add new roles
    #
    model($c, 'UserRole')->search(
        { user_id => $id },
    )->delete();
    for my $r (_get_roles($c)) {
        model($c, 'UserRole')->create({
            user_id => $id,
            role_id => $r,
        });
    }

    $c->response->redirect($c->uri_for("/user/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $u = $c->stash->{user}
        = model($c, 'User')->find($id);
    $c->stash->{template} = "user/view.tt2";
}

sub create : Local {
    my ($self, $c, $user_id) = @_;

    $c->stash->{role_table}  = role_table($c);
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "user/create_edit.tt2";
}

#
# get the set and implied roles from the request params
#
# 1 super admin
# 2 program admin
# 3 mailing list admin
# 4 program staff
# 5 mailing list staff
# 6 web designer
# 7 membership admin
# 8 field staff
# 9 mmi admin
#
sub _get_roles {
    my ($c) = @_;
    my %cur_roles = map { $_ => 1 }
                    grep {  s{^role(\d+)}{$1}  }
                    keys %{$c->request->params};
    # ensure additional roles are in place - don't dup code ???
    if ($cur_roles{1}) {
        @cur_roles{ 2..7, 9 } = 1;
    }
    elsif ($cur_roles{6}) {
        @cur_roles{ 2..5 } = 1;
    }
    elsif ($cur_roles{2}) {
        $cur_roles{4} = 1;
    }
    elsif ($cur_roles{3}) {
        $cur_roles{5} = 1;
    }
    elsif ($cur_roles{7}) {
        $cur_roles{5} = 1;
    }
    return keys %cur_roles;
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;

    my $u = model($c, 'User')->create(\%hash);
    my $id = $u->id;

    for my $r (_get_roles($c)) {
        model($c, 'UserRole')->create({
            user_id => $id,
            role_id => $r,
        });
    }

    $c->response->redirect($c->uri_for("/user/view/$id"));
}

sub profile : Local {
    my ($self, $c) = @_;

    $c->stash->{user} = $c->user;
    $c->stash->{template} = "user/profile.tt2";
}

sub profile_do : Local {
    my ($self, $c) = @_;

    my $cur_pass  = $c->request->params->{cur_pass};
    my $good_pass = $c->user->password;
    my $new_pass  = $c->request->params->{new_pass};
    my $new_pass2 = $c->request->params->{new_pass2};
    my @pass = ();
    if ($cur_pass) {
        @mess = ();
        if ($good_pass ne $cur_pass) {
            push @mess, "Current password is not correct.";
        }
        elsif ($new_pass ne $new_pass2) {
            push @mess, "New passwords do not match.";
        }
        else {
            check_password($new_pass);
        }
        if (@mess) {
            $c->stash->{mess} = join "<br>\n", @mess;
            $c->stash->{template} = "user/error.tt2";
            return;
        }
        @pass = (password => $new_pass);
    }
    $c->user->update({
        @pass,
        first    => $c->request->params->{first},
        last     => $c->request->params->{last},
        email    => $c->request->params->{email},
        office   => $c->request->params->{office},
        cell     => $c->request->params->{cell},
        txt_msg_email => $c->request->params->{txt_msg_email},
    });
    $c->stash->{template} = "configuration/index.tt2";
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
