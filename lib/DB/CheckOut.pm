use strict;
use warnings;
package DB::CheckOut;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS check_out;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE check_out (
book_id integer,
person_id integer,
due_date text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO check_out
(book_id, person_id, due_date) 
VALUES
(?, ?, ?)
EOS
}

1;
