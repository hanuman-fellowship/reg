use strict;
use warnings;
package DB::Program;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS program;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE program (
    id
    name
    title
    subtitle
    glnum
    housecost_id
    retreat
    sdate
    edate
    tuition
    confnote
    url
    webdesc
    webready
    image
    kayakalpa
    canpol_id
    extradays
    full_tuition
    deposit
    req_pay
    collect_total
    linked
    unlinked_dir
    ptemplate
    cl_template
    sbath
    single
    economy
    commuting
    footnotes
    reg_start
    reg_end
    prog_start
    prog_end
    reg_count
    lunches
    school_id
    level_id
    max
    notify_on_reg
    summary_id
    rental_id
    do_not_compute_costs
    dncc_why
    color
    allow_dup_regs
    percent_tuition
    refresh_days
    category_id
    facebook_event_id
    not_on_calendar
    tub_swim
    cancelled
    pr_alert
    bank_account
    waiver_needed
    housing_not_needed
    program_created
    created_by
    badge_title
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO program
(id, name, title, subtitle, glnum, housecost_id, retreat, sdate, edate, tuition, confnote, url, webdesc, webready, image, kayakalpa, canpol_id, extradays, full_tuition, deposit, req_pay, collect_total, linked, unlinked_dir, ptemplate, cl_template, sbath, single, economy, commuting, footnotes, reg_start, reg_end, prog_start, prog_end, reg_count, lunches, school_id, level_id, max, notify_on_reg, summary_id, rental_id, do_not_compute_costs, dncc_why, color, allow_dup_regs, percent_tuition, refresh_days, category_id, facebook_event_id, not_on_calendar, tub_swim, cancelled, pr_alert, bank_account, waiver_needed, housing_not_needed, program_created, created_by, badge_title) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
