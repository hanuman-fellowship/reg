use strict;
use warnings;
package RetreatCenter::Controller::Login;
use base 'Catalyst::Controller';

use Global qw/%string/;

sub index : Private {
    my ($self, $c) = @_;

    # if already logged in ...
    if ($c->user_exists()) {
        $c->response->redirect($c->uri_for('/person/search'));
        return;
    }
    # Get the username and password from form
    my $username = $c->request->params->{username} || "";
    my $password = $c->request->params->{password} || "";

    # If the username and password values were found in form
    if ($username && $password) {
        # Attempt to log the user in
        if ($c->login($username, $password)) {
            # If successful, then let them use the application.
            Global->init($c);       # where else to put this???
            $c->response->redirect($c->uri_for('/person/search'));
            return;
        }
        else {
            $c->stash->{error_msg} = "Bad username or password.";
        }
    }
    # If either of above don't work out, send to the login page
    $c->stash->{template} = 'login.tt2';
}

1;
