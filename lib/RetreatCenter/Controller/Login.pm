use strict;
use warnings;
package RetreatCenter::Controller::Login;
use base 'Catalyst::Controller';

sub index : Private {
    my ($self, $c) = @_;

    # Get the username and password from form
    my $username = $c->request->params->{username} || "";
    my $password = $c->request->params->{password} || "";

    # If the username and password values were found in form
    if ($username && $password) {
        # Attempt to log the user in
        if ($c->login($username, $password)) {
            # If successful, then let them use the application
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
