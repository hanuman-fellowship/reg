use strict;
use warnings;
package DB::Cluster;
use DBH;

sub order { 1 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS cluster;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE cluster (
id $pk
name varchar(30) $sdn,
type char(10) $sdn,
cl_order tinyint $idn
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO cluster
(name, type, cl_order) 
VALUES
(?, ?, ?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my (@fields) = split /\|/, $line, -1;
        $sth->execute(@fields);
    }
}

1;

__DATA__
Conference Center 1st|indoors|1
Conference Center 2nd|indoors|2
Seminar House|indoors|3
RAM|indoors|4
Oaks Own Tent|outdoors|5
Oaks Center Tent|outdoors|6
Madrone Own Tent|outdoors|7
Madrone Center Tent|outdoors|8
Oak Cabins|indoors|9
CB Terrace|outdoors|10
Miscellaneous|special|11
School|special|12
