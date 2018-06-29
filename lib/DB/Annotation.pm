use strict;
use warnings;
package DB::Annotation;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS annotation;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE annotation (
    id
    cluster_type
    label
    x
    y
    x1
    y1
    x2
    y2
    shape
    thickness
    color
    inactive
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO annotation
(id, cluster_type, label, x, y, x1, y1, x2, y2, shape, thickness, color, inactive) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
