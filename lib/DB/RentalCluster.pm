use strict;
use warnings;
package DB::RentalCluster;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS rental_cluster;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE rental_cluster (
    rental_id
    cluster_id
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO rental_cluster
(rental_id, cluster_id) 
VALUES
(?, ?)
EOS
}

1;
