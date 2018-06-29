use strict;
use warnings;
package DB::Role;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS role;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE role (
    id
    role
    fullname
    descr
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO role
(id, role, fullname, descr) 
VALUES
(?, ?, ?, ?)
EOS
}

1;
