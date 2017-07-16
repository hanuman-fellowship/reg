#!/usr/local/bin/perl
use strict;
use warnings;
use lib 'lib';
use Util qw/
    model
    db_init
    rand6
/;

use RetreatCenterDB;
my $c = db_init();
for my $p (model($c, 'Person')->search({
               secure_code => '',
           })
) {
    $p->update({
        secure_code => rand6($c),
    });
    print $p->id, $p->first, $p->last, $p->secure_code, "\n";
}
