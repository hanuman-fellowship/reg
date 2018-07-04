use strict;
use warnings;
package DB::Exception;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS exception;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE exception (
    prog_id
    tag
    value
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO exception
(prog_id, tag, value) 
VALUES
(?, ?, ?)
EOS
}

1;
