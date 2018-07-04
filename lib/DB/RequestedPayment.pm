use strict;
use warnings;
package DB::RequestedPayment;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS req_payment;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE req_payment (
    id
    org
    person_id
    amount
    for_what
    the_date
    reg_id
    note
    code
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO req_payment
(id, org, person_id, amount, for_what, the_date, reg_id, note, code) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
