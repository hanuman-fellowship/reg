use strict;
use warnings;
package DB::String;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS string;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE string (
    the_key VARCHAR(30),
    value   VARCHAR(200)
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO string
(the_key, value) 
VALUES
(?, ?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my ($key, $val) = split /\s+/, $line;
        $sth->execute($key, $val);
    }
}

1;

__DATA__
abcdefghij 123456789012345678901234567890123456789012345678901234567890
z 3
w 4
