use strict;
use warnings;
package DB::XAccount;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS xaccount;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE xaccount (
id integer primary key autoincrement,
descr text,
glnum text,
sponsor text
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
