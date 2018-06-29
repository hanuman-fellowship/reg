use strict;
use warnings;
package DB::House;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS house;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE house (
    id
    name
    max
    bath
    tent
    center
    cabin
    priority
    x
    y
    cluster_id
    cluster_order
    inactive
    disp_code
    comment
    resident
    cat_abode
    sq_foot
    key_card
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO house
(id, name, max, bath, tent, center, cabin, priority, x, y, cluster_id, cluster_order, inactive, disp_code, comment, resident, cat_abode, sq_foot, key_card) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
