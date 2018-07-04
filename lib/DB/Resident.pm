use strict;
use warnings;
package DB::Resident;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS resident;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE resident (
    id
    person_id
    comment
    image
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
