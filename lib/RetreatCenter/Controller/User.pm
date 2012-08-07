use strict;
use warnings;
package RetreatCenter::Controller::User;
use base 'Catalyst::Controller';

use Util qw/
    trim
    empty
    role_table
    valid_email
    avail_pic_num
    resize
    model
    stash
    d3_to_hex
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
    my ($c) = @_;

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
        password
        email
    /) {
        $P{$k} = trim($P{$k});
        if (empty($P{$k})) {
            push @mess, "\u$k cannot be blank.";
        }
    }
    $P{hide_mmi} = '' unless exists $P{hide_mmi};
    check_password($P{password});
    if ($P{email} && ! valid_email($P{email})) {
        push @mess, "Invalid email: $P{email}";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "user/error.tt2";
    }
}

sub check_password {
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

    _get_data($c);
    return if @mess;

    my $user =  model($c, 'User')->find($id);
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
# 12 driver
# 13 ride admin
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
        @cur_roles{ 2..7, 9, 13, 14, 15 } = 1;
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

    my $u = model($c, 'User')->create(\%P);
    my $id = $u->id;

    for my $r (_get_roles($c)) {
        model($c, 'UserRole')->create({
            user_id => $id,
            role_id => $r,
        });
    }

    $c->response->redirect($c->uri_for("/user/view/$id"));
}

sub profile_view : Local {
    my ($self, $c, $msg) = @_;

    my $u = $c->user();
    stash($c,
        msg       => ($msg? "Password was changed.": ""),        # hack
        user      => $u,
        user_bg   => d3_to_hex($u->bg()   || '255,255,255'),   # black
        user_fg   => d3_to_hex($u->fg()   || '  0,  0,  0'),   # white
        user_link => d3_to_hex($u->link() || '  0,  0,255'),   # blue
        pictures  => _pictures($u->obj->id()),
        template  => "user/profile_view.tt2",
    );
}

sub _pictures {
    my ($id) = @_;
    my $pics = "";
    my $dels = "";
    my @pics = <root/static/images/uth-$id-*>;
    for my $p (@pics) {
        my $mp = $p;
        $mp =~ s{root}{};
        my ($n) = $p =~ m{(\d+)[.]};
        $pics .= "<td><img src=$mp></td>\n";
        $dels .= "<td align=center><a href='/user/profile_pic_del/$id/$n'>Del</a></td>\n";
    }
    return <<"EOH";
<tr>$pics</tr>
<tr>$dels</tr>
EOH
}

sub profile_pic_del : Local {
    my ($self, $c, $id, $n) = @_;
    unlink <root/static/images/u*$id-$n*>;
    $c->response->redirect($c->uri_for('/user/profile_view'));
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
    $c->response->redirect($c->uri_for('/user/profile_view'));
}

sub profile_new_pic : Local {
    my ($self, $c) = @_;
    if (my $upload = $c->request->upload('newpic')) {
        my $id = $c->user->obj->id();
        my $n = avail_pic_num('u', $id);
        $upload->copy_to("root/static/images/uo-$id-$n.jpg");
        Global->init($c);
        resize('u', "$id-$n");
        my $ftp = Net::FTP->new($string{ftp_site},
                                Passive => $string{ftp_passive})
            or return _pub_err($c, "cannot connect to $string{ftp_site}");
        $ftp->login($string{ftp_login}, $string{ftp_password})
            or return _pub_err($c, "cannot login: " . $ftp->message);
        $ftp->cwd($string{ftp_userpics})
            or return _pub_err($c, "cannot cwd: " . $ftp->message);
        $ftp->binary();
        $ftp->put("root/static/images/ub-$id-$n.jpg", "ub-$id-$n.jpg")
            or return _pub_err($c, "cannot put: " . $ftp->message);
        $ftp->quit();
    }
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
        template => 'user/profile_password.tt2',
    );
}

sub profile_password_do : Local {
    my ($self, $c) = @_;
    my $u = $c->user;
    my $cur_pass  = $c->request->params->{cur_pass};
    my $good_pass = $u->password();
    my $new_pass  = $c->request->params->{new_pass};
    my $new_pass2 = $c->request->params->{new_pass2};
    @mess = ();
    if ($cur_pass) {
        if ($good_pass ne $cur_pass) {
            push @mess, "Current password is not correct.";
        }
        elsif ($new_pass ne $new_pass2) {
            push @mess, "New passwords do not match.";
        }
        else {
            check_password($new_pass);
        }
    }
    else {
        push @mess, "Missing current password.";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "user/error.tt2";
        return;
    }
    $u->update({
        password => $new_pass,
    });
    $c->response->redirect($c->uri_for('/user/profile_view/1'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
