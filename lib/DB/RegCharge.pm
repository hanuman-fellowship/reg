use strict;
use warnings;
package DB::RegCharge;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS reg_charge;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE reg_charge (
    id
    reg_id
    user_id
    the_date
    time
    amount
    what
    automatic
    type
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO reg_charge
(id, reg_id, user_id, the_date, time, amount, what, automatic, type) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
