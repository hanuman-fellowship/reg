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

sub index : Private {
    my ($self, $c) = @_;

    # if already logged in ...
    if ($c->user_exists()) {
        if ($c->user->username() eq 'calendar') {
            $c->response->redirect($c->uri_for('/event/calendar/'
                . today()->as_d8() . "/3"));
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
        if ($c->login($username, $password)) {
            # successful, let them use the application!
            Global->init($c);       # where else to put this???
            _clear_images();
            if ($c->check_user_roles('prog_staff')) {
                $c->response->redirect($c->uri_for('/program/list'));
            }
            elsif ($c->check_user_roles('field_staff')) {
                $c->response->redirect($c->uri_for('/listing/field'));
            }
            elsif ($c->check_user_roles('driver')) {
                $c->response->redirect($c->uri_for('/ride/mine'));
            }
            elsif ($username eq 'calendar') {
                $c->response->redirect($c->uri_for('/event/calendar/'
                    . today()->as_d8()));
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
    # If either of above don't work out, send to the login page
    $c->stash->{template} = 'login.tt2';
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
