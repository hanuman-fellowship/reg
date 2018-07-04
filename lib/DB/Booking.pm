use strict;
use warnings;
package DB::Booking;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS booking;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE booking (
    id
    meet_id
    rental_id
    program_id
    event_id
    sdate
    edate
    breakout
    dorm
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO booking
(id, meet_id, rental_id, program_id, event_id, sdate, edate, breakout, dorm) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
