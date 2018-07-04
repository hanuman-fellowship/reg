use strict;
use warnings;
package DB::XAccount;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS xaccount;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE xaccount (
    id
    descr
    glnum
    sponsor
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO xaccount
(id, descr, glnum, sponsor) 
VALUES
(?, ?, ?, ?)
EOS
}

1;
