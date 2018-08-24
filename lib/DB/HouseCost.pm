use strict;
use warnings;
package DB::HouseCost;
use DBH;

sub order { 1 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS housecost;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE housecost (
id integer primary key auto_increment,
name varchar(255) default '',
single_bath smallint default 0,
single smallint default 0,
dble_bath smallint default 0,
dble smallint default 0,
triple smallint default 0,
dormitory smallint default 0,
economy smallint default 0,
center_tent smallint default 0,
own_tent smallint default 0,
own_van smallint default 0,
commuting smallint default 0,
type char(7) default 'Per Day',
inactive char(3) default ''
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO housecost
(name, single_bath, single, dble_bath, dble, triple, dormitory, economy, center_tent, own_tent, own_van, commuting, type, inactive) 
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
Program 0|110|100|90|80|70|60|50|40|30|20|10|Per Day|
Program 1|111|101|91|81|71|61|51|41|31|21|11|Per Day|
Program 2|112|122|92|82|72|62|52|42|32|22|12|Per Day|
Rental|108|98|88|78|68|58|48|38|28|18|8|Per Day|
Rental Lunch|109|99|89|79|69|59|49|39|29|19|9|Per Day|
TotCost Rental Lunch|400|380|360|340|320|300|280|260|240|220|210|Total|
