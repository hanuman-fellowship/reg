use strict;
use warnings;
package DB::Meal;
use DBH;

sub order { 0 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS meal;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE meal (
id integer primary key auto_increment,
sdate text,
edate text,
breakfast text,
lunch text,
dinner text,
comment text,
user_id integer,
the_date text,
time text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO meal
(id, sdate, edate, breakfast, lunch, dinner, comment, user_id, the_date, time) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
