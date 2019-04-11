use strict;
use warnings;
package RetreatCenter::Controller::Root;
use base 'Catalyst::Controller';

use Util qw/
    tt_today
    email_letter
    d3_to_hex
/;


use JSON;
use GraphQL::Execution qw(execute);
use GraphQL::Type::Library -all;
use DBIx::Class::Schema::Loader;
use GraphQL::Plugin::Convert::DBIC;

{
    package RetreatCenter::Schema;
    use base qw/DBIx::Class::Schema::Loader/;

    my @TABLES = (qw/
      booking
      people
      program
      registration
      rental
    /);

    my $tables = join('|', @TABLES);
    my $constraint = qr/\A(?:$tables)\z/x;

    __PACKAGE__->loader_options(
        constraint   => $constraint,
    );
}

sub _safe_serialize {
  my $data = shift or return 'undefined';
  my $json = encode_json($data);
  $json =~ s#/#\\/#g;
  return $json;
}

sub make_code_closure {
  my ($schema, $root_value, $field_resolver) = @_;
  sub {
    my ($app, $body, $execute) = @_;
    $execute->(
      $schema,
      $body->{query},
      $root_value,
      $app->request->headers,
      $body->{variables},
      $body->{operationName},
      $field_resolver,
    );
  };
};

my $EXECUTE = sub {
  my ($schema, $query, $root_value, $per_request, $variables, $operationName, $field_resolver) = @_;
  execute(
    $schema,
    $query,
    $root_value,
    $per_request,
    $variables,
    $operationName,
    $field_resolver,
  );
};

sub graphql :Local {
    my($self, $c) = @_;

    my $schema = RetreatCenter::Schema->connect(@{$c->model('RetreatCenterDB')->schema->storage->connect_info});
    my $graphql_schema = GraphQL::Plugin::Convert::DBIC->to_graphql($schema);
    
    if(
      (($c->req->headers->header('Accept')//'') =~ /^text\/html\b/) and
      !defined $c->req->query_params->{'raw'}
    ) {
        $c->stash(
          nowrapper => 1,
          title            => 'GraphiQL',
          graphiql_version => 'latest',
          queryString      => _safe_serialize( $c->req->query_params->{'query'} ),
          operationName    => _safe_serialize( $c->req->query_params->{'operationName'} ),
          resultString     => _safe_serialize( $c->req->query_params->{'result'} ),
          variablesString  => _safe_serialize( $c->req->query_params->{'variables'} ),    
        );
        return $c->detach;
    }

    my $handler = sub {
        my ($c, $body, $execute) = @_;
        $execute->(
            $graphql_schema->{schema},
            $body->{query},
            $graphql_schema->{root_value},
            $c->req->headers,
            $body->{variables},
            $body->{operationName},
            $graphql_schema->{resolver},
          );
    };

    my $body_data = $c->req->body_data;
    my $data = $handler->($c, $body_data, $EXECUTE);
    
    $c->res->body( encode_json $data);
}


sub index : Private {
    my ($self, $c) = @_;

    $c->response->redirect($c->uri_for('/login'));
}

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
        if (!$c->debug) {
            $c->stash->{template} = "fatal_error.tt2";
            my $user = $c->user();
            if ($user->username() ne 'sahadev') {
                email_letter($c,
                    to      => 'Jon Bjornstad <jonb@logicalpoetry.com>',
                    from    => $user->name_email(),
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
}

# Note that 'auto' runs after 'begin' but before your actions and that
# 'auto' "chain" (all from application path to most specific class are run)
# See the 'Actions' section of 'Catalyst::Manual::Intro' for more info.
#
sub auto : Private {
    my ($self, $c) = @_;

    Global->init($c);

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
