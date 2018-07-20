use strict;
use warnings;
package DB::MeetingPlace;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS meeting_place;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE meeting_place (
id integer primary key autoincrement,
abbr varchar(10),
name varchar(20),
max tinyint,
disp_ord tinyint,
sleep_too char(3),
color char(15)
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO meeting_place
(abbr, name, max, disp_ord, sleep_too, color) 
VALUES
(?, ?, ?, ?, ?, ?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my (@fields) = split /\|/, $line, -1;
        $sth->execute(@fields);
    }
}

1;

__DATA__
CC|CC Main|500|2|150, 180, 240|
SH MAIN|Seminar House|75|3|255, 170, 240|yes
OH|Orchard House|30|4|30, 175, 10|
CB|CB Main|250|5|210, 240, 255|
CC L|CC Lounge|20|6|210, 230, 250|
AR|Assembly Room|250|7|255, 185, 45|
WW|CB West Wing|30|8|230, 220, 215|
FE|CB Far East|40|9|170,170,230|
KKWC|Kaya Kalpa|10|10|250, 120, 255|yes
NW|No Where|10|1|255, 180, 180|
