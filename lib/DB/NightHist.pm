use strict;
use warnings;
package DB::NightHist;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS night_hist;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE night_hist (
id integer primary key autoincrement,
member_id integer,
reg_id integer,
num_nights text,
action text,
user_id integer,
the_date text,
time text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO night_hist
(id, member_id, reg_id, num_nights, action, user_id, the_date, time) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
