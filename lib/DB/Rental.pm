use strict;
use warnings;
package DB::Rental;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS rental;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE rental (
id integer primary key autoincrement,
name text,
title text,
subtitle text,
glnum text,
sdate text,
edate text,
url text,
webdesc text,
linked text,
phone text,
email text,
comment text,
housecost_id integer,
max text,
expected text,
balance text,
contract_sent text,
sent_by text,
contract_received text,
received_by text,
tentative text,
start_hour text,
end_hour text,
coordinator_id integer,
cs_person_id integer,
lunches text,
status text,
deposit text,
summary_id integer,
mmc_does_reg text,
program_id integer,
proposal_id integer,
color text,
housing_note text,
grid_code text,
staff_ok text,
rental_follows text,
refresh_days text,
cancelled text,
fixed_cost_houses text,
fch_encoded text,
grid_stale text,
pr_alert text,
arrangement_sent text,
arrangement_by text,
counts text,
grid_max text,
housing_charge text,
rental_created text,
created_by text,
badge_title text,
image text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO rental
(id, name, title, subtitle, glnum, sdate, edate, url, webdesc, linked, phone, email, comment, housecost_id, max, expected, balance, contract_sent, sent_by, contract_received, received_by, tentative, start_hour, end_hour, coordinator_id, cs_person_id, lunches, status, deposit, summary_id, mmc_does_reg, program_id, proposal_id, color, housing_note, grid_code, staff_ok, rental_follows, refresh_days, cancelled, fixed_cost_houses, fch_encoded, grid_stale, pr_alert, arrangement_sent, arrangement_by, counts, grid_max, housing_charge, rental_created, created_by, badge_title, image) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
