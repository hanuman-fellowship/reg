use strict;
use warnings;
package DB::RentalCharge;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS rental_charge;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE rental_charge (
    id
    rental_id
    amount
    what
    user_id
    the_date
    time
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO rental_charge
(id, rental_id, amount, what, user_id, the_date, time) 
VALUES
(?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
