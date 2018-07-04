use strict;
use warnings;
package DB::School;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS school;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE school (
    id
    name
    mmi
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO school
(id, name, mmi) 
VALUES
(?, ?, ?)
EOS
}

1;
