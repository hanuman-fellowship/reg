use strict;
use warnings;
package DB::ConfHistory;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS conf_history;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE conf_history (
id integer primary key autoincrement,
reg_id integer,
note text,
user_id integer,
the_date text,
time text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO conf_history
(id, reg_id, note, user_id, the_date, time) 
VALUES
(?, ?, ?, ?, ?, ?)
EOS
}

1;
