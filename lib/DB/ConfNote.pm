use strict;
use warnings;
package DB::ConfNote;
use DBH;

sub order { 0 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS confnote;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE confnote (
id integer primary key auto_increment,
abbr text,
expansion text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO confnote
(id, abbr, expansion) 
VALUES
(?, ?, ?)
EOS
}

1;
