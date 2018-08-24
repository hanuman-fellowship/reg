use strict;
use warnings;
package DB::Config;
use DBH;

sub order { 2 }     # needs House

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS config;
EOS
    $dbh->do(<<"EOS");
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

    #
    # we'll add config records a week back
    # and 6 months into the future.
    #
    my $start = $today - 7;
    my $end = $today + 6*31;
    while ($end->day != 1) {
        ++$end;
    }
    --$end;
    my @dates;
    for (my $d = $start; $d <= $end; ++$d) {
        push @dates, $d->as_d8();
    }
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO config
(house_id, the_date, sex, curmax, cur, program_id, rental_id) 
VALUES
(?, ?, ?, ?, ?, ?, ?)
EOS
    my $house_sth = $dbh->prepare(<<"EOS");
SELECT id, max
  FROM house
EOS
    $house_sth->execute();
    while (my ($h_id, $max) = $house_sth->fetchrow_array()) {
        for my $dt (@dates) {
            $sth->execute($h_id, $dt, 'U', $max, 0, 0, 0);
        }
    }
    my $str_sth = $dbh->prepare(<<"EOS");
UPDATE string
   SET value = '$dates[-1]'
 WHERE the_key = 'sys_last_config_date'
EOS
    $str_sth->execute();
}

1;
