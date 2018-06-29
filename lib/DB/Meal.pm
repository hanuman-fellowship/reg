use strict;
use warnings;
package DB::Meal;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS meal;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE meal (
    id
    sdate
    edate
    breakfast
    lunch
    dinner
    comment
    user_id
    the_date
    time
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO meal
(id, sdate, edate, breakfast, lunch, dinner, comment, user_id, the_date, time) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
