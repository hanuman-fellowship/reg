use strict;
use warnings;
package DB::School;
use DBH;

sub order { 1 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS school;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE school (
id integer primary key auto_increment,
name varchar(50),
mmi char(3)
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO school
(name, mmi) 
VALUES
(?, ?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my (@fields) = split /\|/, $line, -1;
        $sth->execute(@fields);
    }
}

1;

__DATA__
MMC|
MMI School of Yoga|yes
MMI College of Ayurveda|yes
MMI School of Professional Massage|yes
MMI School of Community Studies|yes
