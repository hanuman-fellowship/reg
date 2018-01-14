use strict;
use warnings;
package RetreatCenter::Controller::Login;
use base 'Catalyst::Controller';

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
/;
use Time::Simple qw/
    get_time
/;

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

    # if already logged in ...
    if ($c->user_exists()) {
        my $username = $c->user->username();
        if ($username eq 'calendar') {
            $c->response->redirect($c->uri_for('/event/calendar/'
                . today()->as_d8() . "/3"));
        }
        elsif ($username eq 'library') {
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
        # Attempt to log the user in
        if ($password ne '-no login-'
            && $c->authenticate({
                   username => $username,
                   password => $password,
                })
        ) {
            # successful, let them use the application!
            _clear_images();
            if ($c->check_user_roles('super_admin')) {
                $c->response->redirect($c->uri_for('/person/search'));
            }
            #elsif ($c->check_user_roles('ride_admin')) {
            #    $c->response->redirect($c->uri_for('/ride/list'));
            #}
            elsif ($c->check_user_roles('prog_staff')) {
                if (today()->as_d8() > $string{date_coming_going_printed}) {
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
            elsif ($c->check_user_roles('driver')) {
                $c->response->redirect($c->uri_for('/ride/mine'));
            }
            elsif ($username eq 'calendar') {
                # tried a redirect - did not work when calling
                # via LWP::Simple->get()
                # so, instead we go direct:
                #
                RetreatCenter::Controller::Event->calendar(
                    $c, today()->as_d8(), ""
                );
                return;
            }
            elsif ($username eq 'library') {
                $c->response->redirect($c->uri_for('/book/search'));
            }
            else {
                $c->response->redirect($c->uri_for('/person/search'));
            }
            return;
        }
        else {
            $c->stash->{error_msg} = "Bad username or password.";
        }
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
        if (! @users) {
            stash($c,
                message  => 'There is no such email address in our system.',
                email    => $email,
                template => 'forgot_password.tt2',
            );
            return;
        }
        my $user = $users[0];
        my $username = $user->username;
        my $new_pass = randpass();
        $user->update({
            password => $new_pass,
        });
        my $url = $c->uri_for('/login');
        email_letter($c,
            to      => $user->name_email(),
            from    => "$string{from_title} <$string{from}>",
            subject => "Your account in Reg for MMC",
            html    => <<"EOH",
The password for your account '$username' in Reg for MMC<br>
has been reset to '$new_pass'.
<p>
Here is the <a href='$url'>login page</a>.
<p>
Please change your password to something that you can<br>
easily remember (but hard to guess!).  Do this by choosing:
<ul>
Configuration > User Profile > Password
</ul>
EOH
        );
        stash($c,
            username => $username,
            email    => $email,
            template => 'password_sent.tt2',
        );
        return;
    }
    # send to the login page
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
#
sub _clear_images {
    my $now = sprintf("%04d%02d%02d%02d%02d%02d",
                      (localtime())[reverse (0 .. 5)]);
    for my $im (<root/static/images/im*.png>) {
        my $stamp = substr($im, -18, 14);
        if ($now - $stamp > 120) {
            # that arithmetic is suspect. does it matter???
            unlink $im;
        }
    }
}

1;
