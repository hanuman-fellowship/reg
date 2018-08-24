use strict;
use warnings;
package DB::Organization;
use DBH;

sub order { 1 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS organization;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE organization (
id integer primary key auto_increment,
name varchar(20),
on_prog_cal char(3),
color char(15)
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO organization
(name, on_prog_cal, color) 
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
MMC Programs|yes|185, 185, 255
MMS|yes|255, 155, 155
MMI|yes|205, 255, 255
Temple||255,255,255
SALT||255,255,255
HF Board||255, 255, 115
Maintenance||255, 115, 95
