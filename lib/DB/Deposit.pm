use strict;
use warnings;
package DB::Deposit;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS deposit;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE deposit (
    id
    user_id
    time
    date_start
    date_end
    cash
    chk
    credit
    online
    sponsor
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO deposit
(id, user_id, time, date_start, date_end, cash, chk, credit, online, sponsor) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
