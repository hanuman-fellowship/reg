use strict;
use warnings;
package DB::Glossary;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS glossary;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE glossary (
    term
    definition
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO glossary
(term, definition) 
VALUES
(?, ?)
EOS
}

1;
