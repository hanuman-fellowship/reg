use strict;
use warnings;
package DB::Rental;
use DBH;

sub order { 0 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS rental;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE rental (
id integer primary key auto_increment,
name varchar(255),
title varchar(255),
subtitle varchar(255),
glnum char(10),
sdate char(8),
edate char(8),
url varchar(255),
webdesc varchar(1027),
linked char(3),
phone varchar(255),
email varchar(255),
comment varchar(255),
housecost_id integer,
max text,
expected text,
balance text,
contract_sent char(8),
sent_by varchar(63),
contract_received char(8),
received_by varchar(63),
tentative char(3),
start_hour char(4),
end_hour char(4),
coordinator_id integer,
cs_person_id integer,
lunches varchar(63),
status varchar(31),
deposit integer,
summary_id integer,
mmc_does_reg char(3),
program_id integer,
proposal_id integer,
color text,
housing_note text,
grid_code char(8),
staff_ok char(3),
rental_follows char(3),
refresh_days varchar(255),
cancelled char(3),
fixed_cost_houses varchar(127),
fch_encoded varchar(127),
grid_stale char(3),
pr_alert varchar(255),
arrangement_sent char(8),
arrangement_by varchar(63),
counts varchar(255),
grid_max integer,
housing_charge integer,
rental_created char(8),
created_by varchar(63),
badge_title varchar(63),
image char(3)
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO rental
(id, name, title, subtitle, glnum, sdate, edate, url, webdesc, linked, phone, email, comment, housecost_id, max, expected, balance, contract_sent, sent_by, contract_received, received_by, tentative, start_hour, end_hour, coordinator_id, cs_person_id, lunches, status, deposit, summary_id, mmc_does_reg, program_id, proposal_id, color, housing_note, grid_code, staff_ok, rental_follows, refresh_days, cancelled, fixed_cost_houses, fch_encoded, grid_stale, pr_alert, arrangement_sent, arrangement_by, counts, grid_max, housing_charge, rental_created, created_by, badge_title, image) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
