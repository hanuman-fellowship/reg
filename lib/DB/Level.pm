use strict;
use warnings;
package DB::Level;
use DBH;

sub order { 1 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS level;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE level (
id integer primary key auto_increment,
name varchar(15),
long_term char(3),
public char(3),
school_id integer,
name_regex varchar(20),
glnum_suffix varchar(10)
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO level
(name, long_term, public, school_id, name_regex, glnum_suffix) 
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
Course|||0||
Public Course||yes|0||
CS YSC1|yes||5|YSC\s*1|4YSC1
CS YSC2|yes||5|YSC\s*2|4YSC2
CS YSL1|yes||5|YSL\s*1|4YSL1
CS YSL2|yes||5|YSL\s*2|4YSL2
YTT 200M|yes||2|YTT\s*200\s*M|1200M
YTT 200S|yes||2|YTT\s*200\s*S|1200S
YTT 300|yes||2|YTT\s*300|1300M
AHC|yes||3|AHC|2AHC1
CAP|yes||3|CAP|2CAP1
Diploma|yes||0||
Certificate|yes||0||
Masters|yes||3|masters|2MAS1
