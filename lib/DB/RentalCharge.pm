use strict;
use warnings;
package DB::RentalCharge;
use DBH;

sub order { 0 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS rental_charge;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE rental_charge (
id integer primary key auto_increment,
rental_id integer,
amount text,
what text,
user_id integer,
the_date text,
time text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO rental_charge
(id, rental_id, amount, what, user_id, the_date, time) 
VALUES
(?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
