use strict;
use warnings;
package DB::HouseCost;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS housecost;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE housecost (
id integer primary key autoincrement,
name varchar(30),
single tinyint,
dble tinyint,
triple tinyint,
dormitory tinyint,
economy tinyint,
center_tent tinyint,
own_tent tinyint,
own_van tinyint,
commuting tinyint,
single_bath tinyint,
dble_bath tinyint,
type char(7),
inactive char(3)
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO housecost
(name, single, dble, triple, dormitory, economy, center_tent, own_tent, own_van, commuting, single_bath, dble_bath, type, inactive) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my (@fields) = split /\|/, $line, -1;
        $sth->execute(@fields);
    }
}

1;

__DATA__
Program 10|100|90|80|70|60|50|40|30|20|25|10|Per Day|
TOTCOST Rental Lunch|400|350|300|250|225|210|200|100|85|90|80|Total|
Rental 2010|90|1|1|1|1|1|1|1|1|1|1|Per Day|yes
Rental|10|10|10|10|10|10|10|10|10|10|10|Per Day|
NEW Rental|300|250|200|150|100|75|50|25|8|10|5|Per Day|yes
Rental w/ Lunch|100|90|80|70|60|50|40|30|10|20|5|Per Day|yes
Program 11|101|91|81|71|61|51|41|31|21|26|11|Per Day|
