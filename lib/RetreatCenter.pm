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
#
# old/original mechanisms for Authentication and Authorization:
#    Authentication
#    Authentication::Store::DBIC
#    Authentication::Credential::Password
#    Authorization::Roles
#    Authorization::ACL
#
# ??Should we use
#   Session::Store::File 
# instead of:
#   Session::Store::FastMmap
# Since we're on Unix we apparently can use:
#   Session::Store::Memcached
#

#    -Debug
#    StackTrace
use Catalyst qw/

    ConfigLoader
    Static::Simple

    Authentication
    Authorization::Roles

    Session
    Session Session::Store::DBIC
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
    psgi_middleware => ['XSendfile'], # Maybe move to prod only config?
    'Plugin::Static::Simple' => {
        'mime_types' => {
            'jpg' => 'image/jpg',
            'gif' => 'image/gif',
            'png' => 'image/png',
        },
        'dirs' => [ 'static', qr/^(images|css)/ ],    
        'ignore_extensions' => [ 'html' ],
    },
    'Plugin::Session' => {
        dbic_class => 'RetreatCenterDB::Session',  # Assuming MyApp::Model::DBIC
        expires    => 3600,
    },
);

# Start the application
__PACKAGE__->setup;

=begin

# authorization rules
# ??? deleting a person requires no authorization???
# view is okay. - but not password for non-super admin.
for my $a (qw/ create create_do update update_do delete /) {
    __PACKAGE__->deny_access_unless("/user/$a", ['user_admin']);
}
for my $a (qw/ list view /) {
    __PACKAGE__->deny_access_unless("/role/$a", ['user_admin']);
}

for my $a (qw/ create create_do update update_do delete view /) {
    __PACKAGE__->deny_access_unless("/resident/$a", ['personnel_admin']);
}

for my $c (qw/ program canpol housecost leader rental cluster house /) {
    ACTION:
    for my $a (qw/ create create_do update update_do delete /) {
        next ACTION if $c eq 'house' && $a eq 'delete';
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

for my $a (qw/ list create create_do update update_do /) {
    __PACKAGE__->deny_access_unless("/member/$a", ['member_admin']);
}
__PACKAGE__->deny_access_unless("/member/delete", ['super_admin']);

=end

1;
