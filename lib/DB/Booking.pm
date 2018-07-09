use strict;
use warnings;
package DB::Booking;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS booking;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE booking (
id integer primary key autoincrement,
meet_id integer,
rental_id integer,
program_id integer,
event_id integer,
sdate text,
edate text,
breakout text,
dorm text
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
