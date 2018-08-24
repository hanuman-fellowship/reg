use strict;
use warnings;
package DB::Deposit;
use DBH;

sub order { 0 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS deposit;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE deposit (
id integer primary key auto_increment,
user_id integer,
time text,
date_start text,
date_end text,
cash text,
chk text,
credit text,
online text,
sponsor text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO deposit
(id, user_id, time, date_start, date_end, cash, chk, credit, online, sponsor) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
