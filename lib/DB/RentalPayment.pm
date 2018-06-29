use strict;
use warnings;
package DB::RentalPayment;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS rental_payment;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE rental_payment (
    id
    rental_id
    user_id
    the_date
    time
    amount
    type
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO rental_payment
(id, rental_id, user_id, the_date, time, amount, type) 
VALUES
(?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
