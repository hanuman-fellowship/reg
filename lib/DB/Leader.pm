use strict;
use warnings;
package DB::Leader;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS leader;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE leader (
id integer primary key autoincrement,
person_id integer,
public_email text,
url text,
image text,
biography text,
assistant text,
l_order text,
just_first text,
inactive text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO leader
(id, person_id, public_email, url, image, biography, assistant, l_order, just_first, inactive) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
