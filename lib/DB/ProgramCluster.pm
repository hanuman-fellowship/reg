use strict;
use warnings;
package DB::ProgramCluster;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS program_cluster;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE program_cluster (
    program_id
    cluster_id
    seq
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO program_cluster
(program_id, cluster_id, seq) 
VALUES
(?, ?, ?)
EOS
}

1;
