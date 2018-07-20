use strict;
use warnings;
package DB::Resident;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS resident;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE resident (
id integer primary key autoincrement,
person_id integer,
comment text,
image text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO resident
(id, person_id, comment, image) 
VALUES
(?, ?, ?, ?)
EOS
}

1;
