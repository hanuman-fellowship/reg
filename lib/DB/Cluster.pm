use strict;
use warnings;
package DB::Cluster;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS cluster;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE cluster (
    id
    name
    type
    cl_order
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO cluster
(id, name, type, cl_order) 
VALUES
(?, ?, ?, ?)
EOS
}

1;
