use strict;
use warnings;
package DB::Credit;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS credit;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE credit (
id integer primary key autoincrement,
person_id integer,
reg_id integer,
date_given text,
amount text,
date_expires text,
date_used text,
used_reg_id integer
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
