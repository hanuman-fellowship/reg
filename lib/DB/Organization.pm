use strict;
use warnings;
package DB::Organization;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS organization;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE organization (
    id
    name
    on_prog_cal
    color
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO organization
(id, name, on_prog_cal, color) 
VALUES
(?, ?, ?, ?)
EOS
}

1;
