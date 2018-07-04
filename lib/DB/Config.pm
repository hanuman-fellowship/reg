use strict;
use warnings;
package DB::Config;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS config;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE config (
    house_id
    the_date
    sex
    curmax
    cur
    program_id
    rental_id
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO config
(house_id, the_date, sex, curmax, cur, program_id, rental_id) 
VALUES
(?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
