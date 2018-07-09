use strict;
use warnings;
package DB::RequestedPayment;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS req_payment;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE req_payment (
id integer primary key autoincrement,
org text,
person_id integer,
amount text,
for_what text,
the_date text,
reg_id integer,
note text,
code text
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
