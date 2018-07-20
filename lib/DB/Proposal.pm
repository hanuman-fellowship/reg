use strict;
use warnings;
package DB::Proposal;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS proposal;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE proposal (
id integer primary key autoincrement,
date_of_call text,
group_name text,
rental_type text,
max text,
min text,
dates_requested text,
checkin_time text,
checkout_time text,
other_things text,
meeting_space text,
housing_space text,
leader_housing text,
special_needs text,
food_service text,
other_requests text,
program_meeting_date text,
denied text,
provisos text,
first text,
last text,
addr1 text,
addr2 text,
city text,
st_prov text,
zip_post text,
country text,
tel_home text,
tel_work text,
tel_cell text,
email text,
cs_first text,
cs_last text,
cs_addr1 text,
cs_addr2 text,
cs_city text,
cs_st_prov text,
cs_zip_post text,
cs_country text,
cs_tel_home text,
cs_tel_work text,
cs_tel_cell text,
cs_email text,
deposit text,
misc_notes text,
rental_id integer,
person_id integer,
cs_person_id integer,
staff_ok text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO proposal
(id, date_of_call, group_name, rental_type, max, min, dates_requested, checkin_time, checkout_time, other_things, meeting_space, housing_space, leader_housing, special_needs, food_service, other_requests, program_meeting_date, denied, provisos, first, last, addr1, addr2, city, st_prov, zip_post, country, tel_home, tel_work, tel_cell, email, cs_first, cs_last, cs_addr1, cs_addr2, cs_city, cs_st_prov, cs_zip_post, cs_country, cs_tel_home, cs_tel_work, cs_tel_cell, cs_email, deposit, misc_notes, rental_id, person_id, cs_person_id, staff_ok) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
