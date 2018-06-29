use strict;
use warnings;
package DB::CanPol;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS canpol;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE canpol (
    id
    name
    policy
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO canpol
(id, name, policy) 
VALUES
(?, ?, ?)
EOS
}

1;
