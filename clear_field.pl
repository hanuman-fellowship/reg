#!/usr/bin/perl
use strict;
use warnings;

use lib 'lib';
use Util qw/
    model
    db_init
/;
use RetreatCenterDB;
my $c = db_init();

# remove a bunch of people
my @people = (
    { first => 'Sephalika', last => 'Senapati'  },
    { first => 'Sridhar',   last => 'Poola'     },
    { first => 'Geetika',   last => 'Arora'     },
    { first => 'Gertrude',  last => 'Flounders' },
    { first => 'Susan',     last => 'Dretzka'   },
    { first => 'Tiki',      last => 'DeGenaro'  },
    { first => 'Bonnie',    last => 'Sandecki'  },
);
for my $p (@people) {
    model($c, 'Person')->search({
        first => $p->{first},
        last  => $p->{last},
    })->delete();
}
my $RST = "root/static";
system("rm -rf $RST/mlist/*");
system("rm -rf $RST/temple/*");
system("rm -rf $RST/online/*");

model($c, 'XAccountPayment')->search()->delete();
