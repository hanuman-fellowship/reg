use strict;
use warnings;
package RetreatCenter::Controller::Logout;
use base 'Catalyst::Controller';

sub index : Private {
    my ( $self, $c ) = @_;

    # Clear the user's state
    $c->logout;
             
    # Send the user to the starting point
    $c->response->redirect($c->uri_for('/'));
}

1;
