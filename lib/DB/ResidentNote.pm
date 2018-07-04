use strict;
use warnings;
package DB::ResidentNote;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS resident_note;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE resident_note (
    id
    resident_id
    the_date
    the_time
    note
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO resident_note
(id, resident_id, the_date, the_time, note) 
VALUES
(?, ?, ?, ?, ?)
EOS
}

1;
