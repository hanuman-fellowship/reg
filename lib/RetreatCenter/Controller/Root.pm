use strict;
use warnings;
package RetreatCenter::Controller::Root;
use base 'Catalyst::Controller';

use Util qw/
    tt_today
    email_letter
    d3_to_hex
/;

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config->{namespace} = '';

sub default : Private {
    my ( $self, $c ) = @_;

    # Hello World
    $c->response->body( $c->welcome_message );
}

sub _set {
    my ($c, $u, $attr, $default) = @_;
    if ($u) {
        if (my $v = $u->$attr) {
            $c->stash->{$attr} = d3_to_hex($v);
        }
        else {
            $c->stash->{$attr} = $default;
        }
    }
    else {
        $c->stash->{$attr} = $default;
    }
}
sub end : ActionClass('RenderView') {
    my ($self, $c) = @_;
    my $u = $c->user;
    _set($c, $u, 'fg', 'black');
    _set($c, $u, 'bg', 'white');
    _set($c, $u, 'link', 'blue');
    if ($u) {
        # tt_today() needs a user.
        $c->stash->{today} = tt_today($c);
    }
    my @errs = @{$c->error()};
    if (@errs) {
        # something went wrong...
        #
        $c->stash->{template} = "fatal_error.tt2";
        my $user = $c->user();
        if ($user->username() ne 'sahadev') {
            email_letter($c,
                to      => 'Jon Bjornstad <jon@logicalpoetry.com>',
                from    => $user->first() . " " . $user->last()
                         . " <" . $user->email() . ">",
                subject => 'Error from Reg',
                html    => $errs[0],
            );
        }
        else {
            $c->stash->{error} = $errs[0];
        }
        $c->clear_errors();
    }
}

# Note that 'auto' runs after 'begin' but before your actions and that
# 'auto' "chain" (all from application path to most specific class are run)
# See the 'Actions' section of 'Catalyst::Manual::Intro' for more info.
#
sub auto : Private {
    my ($self, $c) = @_;

    # Allow unauthenticated users to reach the login page.  This
    # allows anauthenticated users to reach any action in the Login
    # controller.  To lock it down to a single action, we could use:
    #   if ($c->action eq $c->controller('Login')->action_for('index'))
    # to only allow unauthenticated access to the C<index> action we
    # added above.
    if ($c->controller eq $c->controller('Login')) {
        return 1;
    }

    # If a user doesn't exist, force login
    if (!$c->user_exists) {
        # Dump a log message to the development server debug output
        $c->log->debug('***Root::auto User not found, forwarding to /login');

        # Redirect the user to the login page
        $c->response->redirect($c->uri_for('/login'));

        # Return 0 to cancel 'post-auto' processing
        # and prevent use of application
        return 0;
    }
    # User found, so return 1 to continue with processing after this 'auto'
    return 1;
}

1;
