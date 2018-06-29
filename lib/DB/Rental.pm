use strict;
use warnings;
package DB::Rental;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS rental;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE rental (
    id
    name
    title
    subtitle
    glnum
    sdate
    edate
    url
    webdesc
    linked
    phone
    email
    comment
    housecost_id
    max
    expected
    balance
    contract_sent
    sent_by
    contract_received
    received_by
    tentative
    start_hour
    end_hour
    coordinator_id
    cs_person_id
    lunches
    status
    deposit
    summary_id
    mmc_does_reg
    program_id
    proposal_id
    color
    housing_note
    grid_code
    staff_ok
    rental_follows
    refresh_days
    cancelled
    fixed_cost_houses
    fch_encoded
    grid_stale
    pr_alert
    arrangement_sent
    arrangement_by
    counts
    grid_max
    housing_charge
    rental_created
    created_by
    badge_title
    image
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
