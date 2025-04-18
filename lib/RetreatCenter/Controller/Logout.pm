use strict;
use warnings;
package RetreatCenter::Controller::Logout;
use base 'Catalyst::Controller';

sub index : Private {
    my ($self, $c) = @_;

    my $username = $c->user->username();

    # Clear the user's state
    $c->logout;

    if ($username eq 'library') {
        $c->response->redirect("http://www.mountmadonna.org");
    }
    else {
        # Send the user to the starting point
        $c->response->redirect($c->uri_for('/login'));
    }
}

1;
