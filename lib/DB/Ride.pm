use strict;
use warnings;
package DB::Ride;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS ride;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE ride (
    id
    rider_id
    driver_id
    from_to
    pickup_date
    pickup_time
    airport
    carrier
    flight_num
    flight_time
    cost
    type
    comment
    paid_date
    sent_date
    shuttle
    create_date
    create_time
    status
    luggage
    intl
    customs
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO ride
(id, rider_id, driver_id, from_to, pickup_date, pickup_time, airport, carrier, flight_num, flight_time, cost, type, comment, paid_date, sent_date, shuttle, create_date, create_time, status, luggage, intl, customs) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
