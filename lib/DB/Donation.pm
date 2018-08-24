use strict;
use warnings;
package DB::Donation;
use DBH;

sub order { 0 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS donation;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE donation (
id integer primary key auto_increment,
person_id integer,
project_id integer,
the_date text,
amount text,
type text,
who_d text,
date_d text,
time_d text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO donation
(id, person_id, project_id, the_date, amount, type, who_d, date_d, time_d) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
