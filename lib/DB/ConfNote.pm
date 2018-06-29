use strict;
use warnings;
package DB::ConfNote;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS confnote;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE confnote (
    id
    abbr
    expansion
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO confnote
(id, abbr, expansion) 
VALUES
(?, ?, ?)
EOS
}

1;
