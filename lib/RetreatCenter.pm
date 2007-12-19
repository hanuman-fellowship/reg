package RetreatCenter;

use strict;
use warnings;

use Catalyst::Runtime '5.70';

# Set flags and add plugins for the application
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a YAML file in the
#                 application's home directory
# Static::Simple: will serve static files from the application's root 
#                 directory

use Catalyst qw/
    -Debug
    ConfigLoader
    Static::Simple
    StackTrace

    Authentication
    Authentication::Store::DBIC
    Authentication::Credential::Password
    Authorization::Roles
    Authorization::ACL

    Session
    Session::Store::FastMmap
    Session::State::Cookie
/;

our $VERSION = '0.01';

# Configure the application. 
#
# Note that settings in retreatcenter.yml (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with a external configuration file acting as an override for
# local deployment.

__PACKAGE__->config( 
    name => 'RetreatCenter', 
    static => {
                'mime_types' => {
                    'jpg' => 'image/jpg',
                    'gif' => 'image/gif',
                    'png' => 'image/png',
                },
                'dirs'       => [ 'static', qr/^(images|css)/ ],    
                'ignore_extensions' => [ 'html' ],
            }
);

# Start the application
__PACKAGE__->setup;

# authorization rules
for my $p (qw/ program canpol housecost affil leader rental /) {
    for my $a (qw/ create create_do update update_do delete /) {
        __PACKAGE__->deny_access_unless("/$p/$a", ['admin']);
    }
}
for my $a (qw/ leader affil /) {
    for my $a2 (qw/ update update_do /) {
        __PACKAGE__->deny_access_unless("/program/$a\_$a2", ['admin']);
    }
}

1;
