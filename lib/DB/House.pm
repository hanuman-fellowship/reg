use strict;
use warnings;
package DB::House;
use DBH;

sub order { 2 } # needs Cluster

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS house;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE house (
id integer primary key auto_increment,
name varchar(10) default '',
max tinyint default 0,
bath char(3) default '',
tent char(3) default '',
center char(3) default '',
cabin char(3) default '',
priority tinyint default 0,
x smallint default 0,
y smallint default 0,
cluster_id integer default 0,
cluster_order tinyint default 0,
inactive char(3) default '',
disp_code char(3) default '',
comment varchar(255) default '',
resident char(3) default '',
cat_abode char(3) default '',
sq_foot tinyint default 0,
key_card char(3) default ''
)
EOS
}

sub init {
    my $clust_str = $dbh->prepare(<<"EOS");
SELECT id, name
  FROM cluster;
EOS
    $clust_str->execute();
    my %cluster_id_for;
    while (my ($id, $name) = $clust_str->fetchrow_array()) {
        $cluster_id_for{$name} = $id;
    }
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO house
(name, max, bath, tent, center, cabin, priority, x, y, cluster_id, cluster_order, inactive, disp_code, comment, resident, cat_abode, sq_foot, key_card) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my (@fields) = split /\|/, $line, -1;
        for my $f (@fields) {
            $f = undef if $f eq '';
        }
        my $name = $fields[0];
        my $center = $fields[4]; 
        # set cluster_id
        $fields[9] = $name =~ m{\A 1}xms? $cluster_id_for{'Conference Center 1st'}
                    :$name =~ m{\A 2}xms? $cluster_id_for{'Conference Center 2nd'}
                    :$name =~ m{\A SH}xms? $cluster_id_for{'Seminar House'}
                    :$name =~ m{\A RAM}xms? $cluster_id_for{'RAM'}
                    :$name =~ m{\A TCB}xms? $cluster_id_for{'CB Terrace'}
                    :$name =~ m{\A OC}xms? $cluster_id_for{'Oak Cabins'}
                    :$name =~ m{\A MMS}xms? $cluster_id_for{'School'}
                    :$name =~ m{\A OAKS}xms && $center?
                        $cluster_id_for{'Oaks Center Tent'}
                    :$name =~ m{\A OAKS}xms && !$center?
                        $cluster_id_for{'Oaks Own Tent'}
                    :$name =~ m{\A MAD}xms && $center?
                        $cluster_id_for{'Madrone Center Tent'}
                    :$name =~ m{\A MAD}xms && !$center?
                        $cluster_id_for{'Madrone Own Tent'}
                    :
                        $cluster_id_for{'Miscellaneous'}
                    ;
        $sth->execute(@fields);
    }
}

1;

__DATA__
101|2|yes|||yes|18|20|75|1|2|yes|A|||yes|123|yes
102B|2|yes||||10|20|30|1|2||A5|||||yes
103|2|||||17|60|75|1|3||A|||||yes
104B|2|yes||||11|60|30|1|4|yes|A5|yeah||||yes
201|2|||||16|360|75|2|1||A|||||yes
203|2|||||15|400|75|2|3||A|||||yes
SH 1|3|||||3|120|270|3|1||Lt|||||yes
SH 2|7|||||3|120|295|3|2||Lt|||||yes
SH 3|7|||||3|120|345|3|3||Lt|||||yes
SH 4|3|||||3|120|370|3|4||Lt|||||yes
SH 5|1|||||3|75|270|3|5||Lt|||||yes
105H|2|||||13|205|75|1|5||A5|||||yes
107|2|||||12|245|75|1|7||A|hi||||yes
108BH|2|yes||||9|170|30|1|8||A10|||||yes
109|2|||||14|100|100|1|9||L|||||yes
110|4|||||20|150|100|1|10||R|||||yes
111|2|||||11|100|125|1|11||L|||||yes
112B|2|yes||||8|150|125|1|12||R|||||yes
113|2|||||10|100|150|1|13||L|||||yes
114B|2|yes||||7|150|150|1|14||R|||||yes
115|2|||||9|100|175|1|15||L|||||yes
116B|2|yes||||6|150|175|1|16||R|||||yes
117|2|||||2|100|200|1|17||L|||||
118B|2|yes||||2|150|200|1|18||R|||||yes
209|1|||||8|440|100|2|9||L|||||yes
210|4|||||19|490|100|2|10||R|||||yes
202|3|||||21|303|30|2|2||A|||||yes
204|4|||||22|360|30|2|4||A|||||yes
206|4|||||23|417|30|2|6||A|||||yes
208|4|||||24|510|30|2|8||A|||||yes
205|2|||||7|545|75|2|5||A|||||yes
207|2|||||6|585|75|2|7||A|||||yes
211|2|||||5|440|125|2|11||L|||||yes
212B|2|yes||||5|490|125|2|12||R|||||yes
213|2|||||4|440|150|2|13||L|||||yes
214B|2|yes||||4|490|150|2|14||R|||||yes
215|2|||||3|440|175|2|15||L|||||yes
216B|2|yes||||3|490|175|2|16||R|||||yes
217|2|||||1|440|200|2|17||L|||||yes
218B|2|yes||||1|490|200|2|18||R|||||yes
RAM 1A|2|||||3|345|270|4|1||Bt|||||yes
RAM 1B|2|||||3|380|270|4|2||Bt|||||yes
RAM 2A|2|||||3|220|270|4|3||Bt|||||yes
RAM 2B|2|||||3|255|270|4|4||Bt|||||yes
RAM 2C|2|||||3|290|270|4|5||Bt|||||yes
OAKS 11|1||yes|||3|30|60|5|11||Lt|||||
OAKS 12|1||yes|||3|30|85|5|12||Lt|||||
OAKS 13|1||yes|||3|30|110|5|13||Lt|||||
OAKS 14|1||yes|||3|30|135|5|14||Lt|||||
OAKS 15|1||yes|||3|30|160|5|15||Lt|||||
OAKS 19|1||yes|||3|30|185|5|19||Lt|||||
OAKS 20|1||yes|||3|30|210|5|20||Lt|||||
OAKS 16|1||yes|yes||3|135|60|6|16||Lt|||||
OAKS 17|1||yes|yes||3|135|85|6|17||Lt|||||
OAKS 18|1||yes|yes||3|135|110|6|18||Lt|||||
OAKS 23|1||yes|yes||3|135|135|6|23||Lt|||||
OAKS 26|1||yes|yes||3|135|160|6|26||Lt|||||
OAKS 28|1||yes|yes||3|135|185|6|28||Lt|||||
OAKS 30|1||yes|yes||3|135|210|6|30||Lt|||||
MAD 1|1||yes|||3|250|60|7|1||Lt|||||
MAD 4|1||yes|||3|250|85|7|4||Lt|||||
MAD 6|1||yes|||3|250|110|7|6||Lt|||||
MAD 7|1||yes|||3|250|135|7|7||Lt|||||
MAD 9|1||yes|||3|250|160|7|9||Lt|||||
MAD 2|1||yes|yes||3|310|60|8|2||Lt|||||
MAD 3|1||yes|yes||3|310|85|8|3||Lt|||||
MAD 5|1||yes|yes||3|310|110|8|5||Lt|||||
MAD 8|1||yes|yes||3|310|135|8|8||Lt|||||
MAD 10|1||yes|yes||3|310|160|8|10||Lt|||||
MAD A|1||yes|yes||3|350|160|8|11|yes|Lt|||||
MAD B|1||yes|yes||3|390|160|8|12|yes|Lt|||||
OC 1|2||||yes|3|440|270|11|1||Lt|||||yes
OC 2|2||||yes|3|440|295|11|2||Lt|||||yes
OC 3|2||||yes|3|440|320|11|3||Lt|||||yes
OC 4|2||||yes|3|440|345|11|4||Lt|||||yes
OC 5|2||||yes|3|440|370|11|5||Lt|||||yes
OC 6|2||||yes|3|490|270|11|6||Lt|||||yes
OC 7|2||||yes|3|490|295|11|7||Lt|||||yes
OC 8|2||||yes|3|490|320|11|8||Lt|||||yes
OC 9|2||||yes|3|490|345|11|9||Lt|||||yes
TCB 1|1||yes|||9|250|210|12|1|yes|Lt|||||
TCB 2|1||yes|||9|250|235|12|2|yes|Lt|||||
TCB 3|1||yes|||9|250|260|12|3|yes|Lt|||||
TCB 4|1||yes|||9|250|285|12|4|yes|Lt|||||
TCB 5|1||yes|||9|250|310|12|5|yes|Lt|||||
TCB 6|1||yes|||9|250|335|12|6|yes|Lt|||||
TCB 7|1||yes|||9|250|360|12|7|yes|Lt|||||
TCB 8|1||yes|||9|250|385|12|8|yes|Lt|||||
TCB 9|1||yes|||9|250|410|12|9|yes|Lt|||||
TCB 10|1||yes|||9|250|435|12|10|yes|Lt|||||
GDN 3|2|||||9|100|50|13|1||L|||||yes
OH 3|2|yes||||9|100|75|13|2||L|||||yes
LTL HSE|2|yes||||9|100|100|13|4||L|||||yes
KKWC|5|||||9|100|125|13|3||L|||||yes
CC CR|10|||||9|100|150|13|5||L|||||yes
OH MAIN|12|||||9|100|200|13|7||L|||||yes
SH MAIN|20|||||9|100|325|3|8||L|||||yes
MMS A-3|7|||||9|275|50|14|1||Lt|||||yes
MMS B-4|7|||||9|275|75|14|2||Lt|||||yes
MMS C-13|7|||||9|275|100|14|3||Lt|||||
MMS C-14|7|||||9|275|125|14|4||Lt|||||yes
MMS C-16|7|||||9|275|150|14|5||Lt|||||yes
