use strict;
use warnings;
package DB::Ride;
use DBH;

sub order { 0 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS ride;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE ride (
id integer primary key auto_increment,
rider_id integer,
driver_id integer,
from_to text,
pickup_date text,
pickup_time text,
airport text,
carrier text,
flight_num text,
flight_time text,
cost text,
type text,
comment text,
paid_date text,
sent_date text,
shuttle text,
create_date text,
create_time text,
status text,
luggage text,
intl text,
customs text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO ride
(id, rider_id, driver_id, from_to, pickup_date, pickup_time, airport, carrier, flight_num, flight_time, cost, type, comment, paid_date, sent_date, shuttle, create_date, create_time, status, luggage, intl, customs) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
