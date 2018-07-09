use strict;
use warnings;
package DB::Block;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS block;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE block (
id integer primary key autoincrement,
house_id integer,
sdate text,
edate text,
nbeds text,
npeople text,
reason text,
comment text,
allocated text,
user_id integer,
the_date text,
time text,
rental_id integer,
program_id integer,
event_id integer
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO block
(id, house_id, sdate, edate, nbeds, npeople, reason, comment, allocated, user_id, the_date, time, rental_id, program_id, event_id) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
