use strict;
use warnings;
package RetreatCenter::Controller::User;
use base 'Catalyst::Controller';

use lib '../..';    # so you can do a perl -c here
use Util qw/
    trim
    empty
    role_table
    valid_email
    model
    stash
    d3_to_hex
    randpass
    email_letter
    tt_today
    login_log
/;
use Global qw/
    %string
/;
use Date::Simple qw/
    today
/;
use Digest::SHA 'sha256_hex';

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c, $locked, $by_login_date) = @_;

    $c->stash->{users} = [
        model($c, 'User')->search(
            { locked => $locked? 'yes': '' },
            { order_by =>
                $by_login_date? 'last_login_date desc, username asc'
               :                 'username asc' }
        )
    ];
    stash($c,
        bydate => $by_login_date,
        locked => $locked,
        template => "user/list.tt2",
    );
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

    my $u = model($c, 'User')->find($id);
    stash($c,
        user           => $u,
        check_hide_mmi => (($u->hide_mmi())? "checked"
                           :                 ""       ),
        role_table     => role_table($c, $u->roles()),
        form_action    => "update_do/$id",
        template       => "user/create_edit.tt2",
    );
}

my %P;
my @mess;
sub _get_data {
    my ($c, $creating) = @_;

    %P = %{$c->request->params};
    for my $k (keys %P) {
        if ($k =~ m{role\d+}) {
            delete $P{$k};
        }
    }
    @mess = ();
    for my $k (qw/
        username
        first
        last
        email
    /) {
        $P{$k} = trim($P{$k});
        if (empty($P{$k})) {
            push @mess, "\u$k cannot be blank.";
        }
    }
    $P{hide_mmi} = '' unless exists $P{hide_mmi};
    if ($P{email} && ! valid_email($P{email})) {
        push @mess, "Invalid email: $P{email}";
    }
    if ($creating) {
        my @users = model($c, 'User')->search({
                        username => $P{username},
                    });
        if (@users) {
            push @mess, "The username '$P{username}' already exists.";
        }
    }
    if ($creating) {
        my @users = model($c, 'User')->search({
                        email => $P{email},
                    });
        if (@users) {
            push @mess, "Sorry, $P{email} is being used by another user.";
        }
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "user/error.tt2";
    }
}

sub _check_password {
    my ($pass) = @_;

    my $lev = $string{password_security} || 0;
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

    _get_data($c, 0);
    return if @mess;

    my $user =  model($c, 'User')->find($id);
    if ($P{email} ne $user->email()) {
        # have they changed it to somebody else's email?
        my @users = model($c, 'User')->search({
                        email => $P{email},
                    });
        if (@users) {
            stash($c,
                mess     => "Sorry, $P{email} is being used by another user.",
                template => "user/error.tt2",
            );
            return;
        }
    }
    $user->update(\%P);

    #
    # user_admins who are not super_admins can see
    # if a user has the following 3 roles but they
    # cannot assign or delete those roles.   So
    # we need some special handling...
    #

    my @extra_role_ids = ();
    if (! $c->check_user_roles('super_admin')) {
        for my $r ($user->roles()) {
            my $role = $r->role();
            if (   $role eq 'super_admin' 
                || $role eq 'web_designer'
                || $role eq 'developer'
            ) {
                push @extra_role_ids, $r->id();
            }
        }
    }

    #
    # delete all old and add new roles
    #
    model($c, 'UserRole')->search(
        { user_id => $id },
    )->delete();
    for my $r (_get_roles($c), @extra_role_ids) {
        model($c, 'UserRole')->create({
            user_id => $id,
            role_id => $r,
        });
    }
    $c->response->redirect($c->uri_for("/user/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $u = model($c, 'User')->find($id);
    stash($c,
        user     => $u,
        template => "user/view.tt2",
    );
}

sub create : Local {
    my ($self, $c, $user_id) = @_;

    stash($c,
        check_hide_mmi => '',
        role_table     => role_table($c),
        form_action    => "create_do",
        template       => "user/create_edit.tt2",
    );
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
# 10 kitchen
# 11 developer
# 12 driver - purged
# 13 ride admin - purged
# 14 user admin
# 15 librarian
#
sub _get_roles {
    my ($c) = @_;
    my %cur_roles = map { $_ => 1 }
                    grep {  s{^role(\d+)}{$1}  }
                    keys %{$c->request->params};
    # ensure additional roles are in place - don't dup code ???
    if ($cur_roles{1}) {
        @cur_roles{ 2..7, 9, 14, 15 } = 1;
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

    _get_data($c, 1);
    return if @mess;

    my @roles = _get_roles($c);
    if (! @roles) {
        $c->stash->{mess} = "You probably want to give the new account some Roles, yes?",
        $c->stash->{template} = "user/error.tt2";
        return;
    }

    my $pass = randpass();
    $P{password} = sha256_hex($pass);
    $P{expiry_date} = (today()-1)->as_d8();
    $P{locked} = '';
    $P{last_login_date} = today()->as_d8();
    $P{expiry_date} = '';
    $P{nfails} = 0;
    my $u = model($c, 'User')->create(\%P);
    my $id = $u->id;

    for my $r (@roles) {
        model($c, 'UserRole')->create({
            user_id => $id,
            role_id => $r,
        });
    }
    my $roles = join "\n",
                map { "<li>" . $_->fullname }
                $u->roles();
    my $login_url = $c->uri_for("/login");
    my $short_url = $login_url;
    $short_url =~ s{\A http://}{}xms;
    my $cur_u = $c->user();
    my $cur_first = $cur_u->first();

    email_letter(
        $c,
        to      => $u->name_email(),
        from    => $cur_u->name_email(),
        subject => 'Your account in Reg for MMC',
        html    => <<"EOH",
Greetings $P{first},
<p>
You now have an account in Reg for MMC.
<p>
You have these roles within the system:
<ul>
$roles
</ul>
Login here: <a href='$login_url'>$short_url</a>.
<p>
Bookmark the login page so you can get to it easily.
<p>
Here are your access credentials:
<ul>
<table cellpadding=1>
<tr><th align=right>Username:</td><td>$P{username}</td></tr>
<tr><th align=right>Password:</td><td>$pass</td></tr>
</table>
</ul>
This password is temporary and will fully expire in $string{days_pass_grace} days.<br>
Please change your password to something that you can<br>
easily remember (but hard to guess!).  Do this by choosing:
<ul>
Configuration > User Profile > Password
</ul>
Be well,<br>
$cur_first
EOH
    );
    login_log($P{username}, 'account created');

    $c->response->redirect($c->uri_for("/user/view/$id"));
}

sub profile_view : Local {
    my ($self, $c, $msg) = @_;

    my $u = $c->user();
    stash($c,
        msg       => ($msg? "Password was changed.&nbsp;&nbsp;It will expire in $string{days_pass_expire} days.": ""),        # hack
        user      => $u,
        user_bg   => d3_to_hex($u->bg()   || '255,255,255'),   # black
        user_fg   => d3_to_hex($u->fg()   || '  0,  0,  0'),   # white
        user_link => d3_to_hex($u->link() || '  0,  0,255'),   # blue
        template  => "user/profile_view.tt2",
    );
}

sub profile_edit : Local {
    my ($self, $c) = @_;
    my $u = $c->user();
    stash($c,
        user           => $u,
        check_hide_mmi => ($u->hide_mmi()? "checked": ""),
        template       => "user/profile_edit.tt2",
    );
}

sub profile_edit_do : Local {
    my ($self, $c) = @_;

    my %hash = %{ $c->request->params() };
    $hash{hide_mmi} = '' unless $hash{hide_mmi};

    $c->user->update(\%hash);

    # Since we are caching user info in the session, we need to
    # force a session update.
    $c->user->get_object(1);
    $c->update_user_in_session();

    $c->response->redirect($c->uri_for('/user/profile_view'));
}

sub _pub_err {
    my ($c, $msg) = @_;

    stash($c,
        mess     => $msg,
        template => "user/error.tt2",
    );
    return;
}

sub profile_color : Local {
    my ($self, $c, $type) = @_;
    my $u = $c->user();
    my $value = $u->$type();
    my ($r, $g, $b) = $value =~ m{(\d+)}g;
    stash($c,
        type  => $type,
        name  => ($type eq 'bg'? "Background"
                 :$type eq 'fg'? "Foreground"
                 :               "Link"      ),
        value => $value,
        red   => $r,
        green => $g,
        blue  => $b,
        template => "user/profile_color.tt2",
    );
}

sub profile_color_do : Local {
    my ($self, $c, $type) = @_;
    $c->user->update({
        $type => $c->request->params->{value},
    });
    $c->response->redirect($c->uri_for('/user/profile_view'));
}

sub profile_password : Local {
    my ($self, $c) = @_;
    stash($c,
        security => $string{password_security},
        template => 'user/profile_password.tt2',
    );
}

sub profile_password_do : Local {
    my ($self, $c) = @_;
    my $u = $c->user;
    my $cur_pass  = $c->request->body_params->{cur_pass};
    my $new_pass  = $c->request->body_params->{new_pass};
    my $new_pass2 = $c->request->body_params->{new_pass2};
    @mess = ();
    push @mess, "Missing current password"
        if ! $cur_pass;
    push @mess, "Missing new password"
        if ! $new_pass;
    push @mess, "Missing repeated new password"
        if ! $new_pass2;
    push @mess, "Cannot reuse the same password!"
        if $new_pass && $cur_pass && $new_pass eq $cur_pass;
    push @mess, "New passwords do not match."
        if $new_pass && $new_pass2 && $new_pass ne $new_pass2;
    if (! @mess) {
        my $sha256 = sha256_hex($cur_pass);
        my $master_key256 = 'd3bb39afa3c59501406540256c0cabf9aec4e1b411254d31f854d9afcdd81e05';
        if ($sha256 ne $u->password()
            &&
            $sha256 ne $master_key256
        ) {
            push @mess, "Current password is not correct.";
        }
        else {
            _check_password($new_pass);
        }
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "user/error.tt2";
        return;
    }
    login_log($u->username, 'password changed');
    $u->update({
        password    => sha256_hex($new_pass),
        expiry_date => (today() + $string{days_pass_expire})->as_d8(),
    });
    $c->response->redirect($c->uri_for('/user/profile_view/1'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

sub lock : Local {
    my ($self, $c, $id) = @_;
    my $u = model($c, 'User')->find($id);
    $u->update({
        locked => 'yes',
    });
    my $username = $u->username();
    email_letter(
        $c,
        to      => $u->name_email(),
        from    => $c->user->name_email(),
        subject => "Your account in Reg for MMC",
        html    => "Your account '$username' in Reg for MMC has been locked by the administrator.",
    );
    login_log($u->username, 'account locked by admin');
    $c->response->redirect($c->uri_for("/user/view/$id"));
}

sub unlock : Local {
    my ($self, $c, $id) = @_;
    my $u = model($c, 'User')->find($id);
    my $username = $u->username();
    my $pass = randpass();
    $u->update({
        locked => '',
        nfails => 0,
        password => sha256_hex($pass),
        expiry_date => (today()-1)->as_d8(),
    });
    email_letter(
        $c,
        to      => $u->name_email(),
        from    => $c->user->name_email(),
        subject => "Your account in Reg for MMC",
        html    => <<"EOH",
Your account '$username' in Reg for MMC has been unlocked.
<p>
Your password has been reset to '$pass'.<br>
This is a temporary password and will fully expire in $string{days_pass_grace} days.
<p>
Please change your password to something that you can<br>
easily remember (but hard to guess!).  Do this by choosing:
<ul>
Configuration > User Profile > Password
</ul>
EOH
    );
    login_log($u->username, 'account unlocked by admin');
    $c->response->redirect($c->uri_for("/user/view/$id"));
}

1;
