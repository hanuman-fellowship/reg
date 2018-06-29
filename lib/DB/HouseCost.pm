use strict;
use warnings;
package DB::HouseCost;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS housecost;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE housecost (
    id
    name
    single
    dble
    triple
    dormitory
    economy
    center_tent
    own_tent
    own_van
    commuting
    single_bath
    dble_bath
    type
    inactive
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO housecost
(id, name, single, dble, triple, dormitory, economy, center_tent, own_tent, own_van, commuting, single_bath, dble_bath, type, inactive) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
