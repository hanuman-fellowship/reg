use strict;
use warnings;
package DB::Person;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS people;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE people (
last text,
first text,
sanskrit text,
addr1 text,
addr2 text,
city text,
st_prov text,
zip_post text,
country text,
akey text,
tel_home text,
tel_work text,
tel_cell text,
email text,
sex text,
id integer primary key autoincrement,
id_sps text,
date_updat text,
date_entrd text,
comment text,
e_mailings text,
snail_mailings text,
share_mailings text,
deceased text,
inactive text,
safety_form text,
secure_code text,
temple_id integer,
waiver_signed text,
only_temple text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO people
(last, first, sanskrit, addr1, addr2, city, st_prov, zip_post, country, akey, tel_home, tel_work, tel_cell, email, sex, id, id_sps, date_updat, date_entrd, comment, e_mailings, snail_mailings, share_mailings, deceased, inactive, safety_form, secure_code, temple_id, waiver_signed, only_temple) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
