use strict;
use warnings;
package DB::Glossary;
use DBH;

sub order { 0 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS glossary;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE glossary (
term text,
definition text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO glossary
(term, definition) 
VALUES
(?, ?)
EOS
}

1;
