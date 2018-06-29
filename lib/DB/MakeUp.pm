use strict;
use warnings;
package DB::MakeUp;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS make_up;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE make_up (
    house_id
    date_vacated
    date_needed
    refresh
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO make_up
(house_id, date_vacated, date_needed, refresh) 
VALUES
(?, ?, ?, ?)
EOS
}

1;
