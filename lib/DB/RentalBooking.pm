use strict;
use warnings;
package DB::RentalBooking;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS rental_booking;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE rental_booking (
    rental_id
    date_start
    date_end
    house_id
    h_type
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO rental_booking
(rental_id, date_start, date_end, house_id, h_type) 
VALUES
(?, ?, ?, ?, ?)
EOS
}

1;
