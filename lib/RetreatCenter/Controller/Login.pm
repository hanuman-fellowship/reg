use strict;
use warnings;
package RetreatCenter::Controller::Login;
use base 'Catalyst::Controller';
use Digest::MD5 qw(md5_hex);

use Global qw/
    %string
/;
use Date::Simple qw/
    today
/;
use Util qw/
    stash
/;
use Time::Simple qw/
    get_time
/;

sub index : Private {
    my ($self, $c) = @_;

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

    # If the username and password values were found in form
    if ($username && $password) {
        # Attempt to log the user in
        if ($password ne '-no login-' && $c->login($username, md5_hex($password))) {
            # successful, let them use the application!
            Global->init($c);       # where else to put this???
            _clear_images();
            if ($c->check_user_roles('super_admin')) {
                $c->response->redirect($c->uri_for('/person/search'));
            }
            elsif ($c->check_user_roles('ride_admin')) {
                $c->response->redirect($c->uri_for('/ride/list'));
            }
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
    # If either of the above don't work out, send to the login page
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
