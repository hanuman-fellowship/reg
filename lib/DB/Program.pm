use strict;
use warnings;
package DB::Program;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS program;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE program (
id integer primary key autoincrement,
name text,
title text,
subtitle text,
glnum text,
housecost_id integer,
retreat text,
sdate text,
edate text,
tuition text,
confnote text,
url text,
webdesc text,
webready text,
image text,
kayakalpa text,
canpol_id integer,
extradays text,
full_tuition text,
deposit text,
req_pay text,
collect_total text,
linked text,
unlinked_dir text,
ptemplate text,
cl_template text,
sbath text,
single text,
economy text,
commuting text,
footnotes text,
reg_start text,
reg_end text,
prog_start text,
prog_end text,
reg_count text,
lunches text,
school_id integer,
level_id integer,
max text,
notify_on_reg text,
summary_id integer,
rental_id integer,
do_not_compute_costs text,
dncc_why text,
color text,
allow_dup_regs text,
percent_tuition text,
refresh_days text,
category_id integer,
facebook_event_id integer,
not_on_calendar text,
tub_swim text,
cancelled text,
pr_alert text,
bank_account text,
waiver_needed text,
housing_not_needed text,
program_created text,
created_by text,
badge_title text
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
