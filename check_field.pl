#!/usr/local/bin/perl
use strict;
use warnings;

use Test::More tests => 11;
use lib 'lib';
use Util qw/
    model
    db_init
/;
use RetreatCenterDB;
my $c = db_init();
use Global qw/
    %string
    %system_affil_id_for
/;
Global->init($c, 1, 1);

# the second person here has the same temple id
# so we overwrite the demographic data from the first
my @p = model($c, 'Person')->search({
    first => 'Sephalika',
    last  => 'Senapati',
});
if (@p) {
    ok(@p == 1, '1 person');
    my $p = $p[0];
    ok($p->first eq 'Sephalika' && $p->last eq 'Senapati', 'first/last');
    ok($p->tel_cell eq '765-225-7715', 'phone'); 
}
else {
    ok(0, '1 person');
}
# the 3rd occurence of this person should end up with
# 'no change' in the log named 'grab_new_log'.
my $rc = system("grep 'Sephalika.*no change' grab_new_log >/dev/null");
$rc >>= 8;
ok($rc == 0, 'no change for 3rd Sephalika');

# the second person by this name has a different temple_id, phone, and email
# so we create a new person with the same name
@p = model($c, 'Person')->search({
    first => 'Sridhar',
    last  => 'Poola',
});
ok(@p == 2, "2 Poola");

# did we get an XAccount payment for the $93 temple donation?
# and was the person given a 'Temple Guest' affiliation?
# Geetika Arora
@p = model($c, 'Person')->search({
    first => 'Geetika',
    last  => 'Arora',
});
ok(@p == 1, 'Geetika Arora');
if (@p) {
    my $p = $p[0];
    my @payments = $p->payments;
    ok(@payments == 1, '1 payment');
    if (@payments) {
        my $py = $payments[0];
        ok($py->amount == 93, "of \$93");
        ok($py->xaccount->descr eq 'Temple', "to Temple");
    }
    my @af = $p->affils;
    ok(@af == 1, '1 affiliation');
    if (@af) {
        ok($af[0]->descrip eq 'Temple Guest', "to Temple Guest"); 
    }
}
