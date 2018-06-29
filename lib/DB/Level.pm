use strict;
use warnings;
package DB::Level;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS level;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE level (
    id
    name
    long_term
    public
    school_id
    name_regex
    glnum_suffix
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO level
(id, name, long_term, public, school_id, name_regex, glnum_suffix) 
VALUES
(?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
