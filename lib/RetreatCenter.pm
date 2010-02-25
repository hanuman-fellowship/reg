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

    # we have not been looking at these so remove em!
    #-Debug
    #StackTrace
use Catalyst qw/
    ConfigLoader
    Static::Simple

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
# ??? deleting a person requires no authorization???
# view is okay. - but not password for non-super admin.
for my $a (qw/ create create_do update update_do delete /) {
    __PACKAGE__->deny_access_unless("/user/$a", ['user_admin']);
}
for my $a (qw/ list view /) {
    __PACKAGE__->deny_access_unless("/role/$a", ['super_admin']);
}

for my $c (qw/ program canpol housecost leader rental cluster house /) {
    for my $a (qw/ create create_do update update_do delete /) {
        __PACKAGE__->deny_access_unless("/$c/$a", ['prog_admin']);
    }
}
__PACKAGE__->deny_access_unless("/leader/del_confirm", ['prog_admin']);

for my $a (qw/ affil /) {
    __PACKAGE__->deny_access_unless("/affil/delete", ['mail_admin']);
    __PACKAGE__->deny_access_unless("/affil/del_confirm", ['mail_admin']);
}
for my $a (qw/ leader affil /) {
    for my $a2 (qw/ update update_do /) {
        __PACKAGE__->deny_access_unless("/program/$a\_$a2", ['prog_admin']);
    }
}

for my $a (qw/ list delete upload /) {
    __PACKAGE__->deny_access_unless("/template/$a", ['web_designer']);
}

for my $a (qw/ list create create_do update update_do /) {
    __PACKAGE__->deny_access_unless("/member/$a", ['member_admin']);
}
__PACKAGE__->deny_access_unless("/member/delete", ['super_admin']);

1;
