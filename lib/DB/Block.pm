use strict;
use warnings;
package DB::Block;
use DBH;

sub order { 1 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS block;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE block (
id $pk
house_id integer $idn,
sdate char(8) $sdn,
edate char(8) $sdn,
nbeds tinyint $idn,
npeople tinyint $idn,
reason varchar(255) $sdn,
comment varchar(255) $sdn,
allocated char(3) $sdn,
user_id integer $idn,
the_date char(8) $sdn,
time char(4) $sdn,
rental_id integer $idn,
program_id integer $idn,
event_id integer $idn
)
EOS
}

sub init {
    return; # not yet
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO block
(id, house_id, sdate, edate, nbeds, npeople, reason, comment, allocated, user_id, the_date, time, rental_id, program_id, event_id) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
