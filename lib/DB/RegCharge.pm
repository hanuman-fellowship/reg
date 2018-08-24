use strict;
use warnings;
package DB::RegCharge;
use DBH;

sub order { 0 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS reg_charge;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE reg_charge (
id integer primary key auto_increment,
reg_id integer,
user_id integer,
the_date text,
time text,
amount text,
what text,
automatic text,
type text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO reg_charge
(id, reg_id, user_id, the_date, time, amount, what, automatic, type) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
