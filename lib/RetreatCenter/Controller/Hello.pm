use strict;
use warnings;
package RetreatCenter::Controller::Hello;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    model
    stash
/;

sub index : Local {
    my ($self, $c) = @_;

    stash($c,
        template => 'hello/list.tt2',
    );
}

sub demo : Local {
    my ($self, $c, $name, $i) = @_;

    $name ||= 'Sahadev';
    $i ||= 42;
    stash($c,
        template => 'hello/demo.tt2',
        number   => $i,
        name     => $name,
    );
}

1;
