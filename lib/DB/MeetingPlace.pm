use strict;
use warnings;
package DB::MeetingPlace;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS meeting_place;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE meeting_place (
    id
    abbr
    name
    max
    disp_ord
    sleep_too
    color
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO meeting_place
(id, abbr, name, max, disp_ord, sleep_too, color) 
VALUES
(?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
