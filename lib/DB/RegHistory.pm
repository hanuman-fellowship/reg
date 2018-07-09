use strict;
use warnings;
package DB::RegHistory;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS reg_history;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE reg_history (
id integer primary key autoincrement,
reg_id integer,
the_date text,
time text,
user_id integer,
what text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO reg_history
(id, reg_id, the_date, time, user_id, what) 
VALUES
(?, ?, ?, ?, ?, ?)
EOS
}

1;
