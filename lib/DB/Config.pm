use strict;
use warnings;
package DB::Config;
use DBH '$dbh';

sub order { 2 }     # needs House

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS config;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE config (
house_id integer,
the_date char(8),
sex char(1),
curmax tinyint,
cur tinyint,
program_id integer,
rental_id integer
)
EOS
}

sub init {
    my ($class, $today) = @_;

    my @dates;
    for my $i (-7 .. 60) {
        push @dates, ($today + $i)->as_d8();
    }
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO config
(house_id, the_date, sex, curmax, cur, program_id, rental_id) 
VALUES
(?, ?, ?, ?, ?, ?, ?)
EOS
    my $house_sth = $dbh->prepare(<<'EOS');
SELECT id, max
  FROM house
EOS
    $house_sth->execute();
    while (my ($h_id, $max) = $house_sth->fetchrow_array()) {
        for my $dt (@dates) {
            $sth->execute($h_id, $dt, 'U', $max, 0, 0, 0);
        }
    }
}

1;
