use strict;
use warnings;
package DB::Affil;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS affils;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE affils (
    id
    descrip
    system
    selectable
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO affils
(id, descrip, system, selectable) 
VALUES
(?, ?, ?, ?)
EOS
}

1;
