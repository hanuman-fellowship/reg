use strict;
use warnings;
package DB::Category;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS category;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE category (
    id
    name
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO category
(id, name) 
VALUES
(?, ?)
EOS
}

1;
