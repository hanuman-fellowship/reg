use strict;
use warnings;
package DB::Credit;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS credit;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE credit (
    id
    person_id
    reg_id
    date_given
    amount
    date_expires
    date_used
    used_reg_id
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO credit
(id, person_id, reg_id, date_given, amount, date_expires, date_used, used_reg_id) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
