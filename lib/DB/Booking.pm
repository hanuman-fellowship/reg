use strict;
use warnings;
package DB::Booking;
use DBH;

sub order { 0 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS booking;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE booking (
id $pk,
meet_id $idn,
rental_id $idn,
program_id $idn,
event_id $idn,
sdate char(8) $sdn,
edate char(8) $sdn,
breakout char(3) $sdn,
dorm char(3) $sdn
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO booking
(id, meet_id, rental_id, program_id, event_id, sdate, edate, breakout, dorm) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
