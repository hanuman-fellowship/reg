use strict;
use warnings;
package DB::Person;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS people;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE people (
    last
    first
    sanskrit
    addr1
    addr2
    city
    st_prov
    zip_post
    country
    akey
    tel_home
    tel_work
    tel_cell
    email
    sex
    id
    id_sps
    date_updat
    date_entrd
    comment
    e_mailings
    snail_mailings
    share_mailings
    deceased
    inactive
    safety_form
    secure_code
    temple_id
    waiver_signed
    only_temple
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
