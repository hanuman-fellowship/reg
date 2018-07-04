use strict;
use warnings;
package DB::Proposal;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS proposal;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE proposal (
    id
    date_of_call
    group_name
    rental_type
    max
    min
    dates_requested
    checkin_time
    checkout_time
    other_things
    meeting_space
    housing_space
    leader_housing
    special_needs
    food_service
    other_requests
    program_meeting_date
    denied
    provisos
    first
    last
    addr1
    addr2
    city
    st_prov
    zip_post
    country
    tel_home
    tel_work
    tel_cell
    email
    cs_first
    cs_last
    cs_addr1
    cs_addr2
    cs_city
    cs_st_prov
    cs_zip_post
    cs_country
    cs_tel_home
    cs_tel_work
    cs_tel_cell
    cs_email
    deposit
    misc_notes
    rental_id
    person_id
    cs_person_id
    staff_ok
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
