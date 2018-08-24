use strict;
use warnings;
package DB::Annotation;
use DBH;

sub order { 1 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS annotation;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE annotation (
id $pk
cluster_type char(10) $sdn,
label char(20) $sdn,
x smallint $idn,
y smallint $idn,
x1 smallint $idn,
y1 smallint $idn,
x2 smallint $idn,
y2 smallint $idn,
shape char(20) $sdn,
thickness tinyint $idn,
color char(15) $sdn,
inactive char(3) $sdn
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO annotation
(cluster_type, label, x, y, x1, y1, x2, y2, shape, thickness, color, inactive) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my (@fields) = split /\|/, $line, -1;
        for my $f (@fields) {
            $f = undef if $f eq '';
        }
        $sth->execute(@fields);
    }
}

1;

__DATA__
indoors|Conference|260|140|||||none|||
indoors|Center|280|155|||||none|||
indoors|Seminar House|80|245|||||none|||
indoors|Ram Cluster|265|245|||||none|||
indoors|Oaks Cabins|425|245|||||none|||
indoors|M|115|78|||||none||0,0,255|
indoors|F|150|78|||||none||255,0,0|
indoors|BH|175|78|||||none||255,0,0|
indoors|M|455|78|||||none||0,0,255|
indoors|F|490|78|||||none||255,0,0|
indoors|F|515|78|||||none||255,0,0|
indoors|Laundry|560|34|||||none||90,90,90|
special|Miscellaneous|75|25|||||none|||
special|School|275|25|||||none|||
outdoors|Oaks|95|17|||||none|||
outdoors|Own|47|37|||||none|||
outdoors|Center|138|37|||||none|||
outdoors|Own|240|37|||||none|||
outdoors|Center|290|37|||||none|||
outdoors|Madrone|257|17|||||none|||
outdoors|Own|370|37|||||none|||
outdoors|Center|415|37|||||none|||
outdoors|CB Terrace|300|188|||||none|||yes
indoors|M|80|298|||||none||0,0,255|
indoors|F|80|348|||||none||255,0,0|
