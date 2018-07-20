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
name varchar(255),
title varchar(255),
subtitle varchar(255),
glnum varchar(15),
housecost_id integer,
retreat char(3),
sdate char(8),
edate char(8),
tuition smallint,
confnote varchar(1023),
url varchar(255),
webdesc varchar(1023),
webready char(3),
image varchar(255),
kayakalpa char(3),
canpol_id integer,
extradays tinyint,
full_tuition smallint,
deposit smallint,
req_pay char(3),
collect_total char(3),
linked char(3),
unlinked_dir varchar(255),
ptemplate varchar(255),
cl_template varchar(255),
sbath char(3),
single char(3),
economy char(3),
commuting char(3),
footnotes varchar(255),
reg_start char(4),
reg_end char(4),
prog_start char(4),
prog_end char(4),
reg_count smallint,
lunches varchar(255),
school_id integer,
level_id integer,
max smallint,
notify_on_reg varchar(255) ,
summary_id integer,
rental_id integer,
do_not_compute_costs char(3),
dncc_why varchar(255),
color char(15),
allow_dup_regs char(3),
percent_tuition tinyint,
refresh_days varchar(255),
category_id integer,
facebook_event_id integer,
not_on_calendar char(3),
tub_swim char(3),
cancelled char(3),
pr_alert varchar(255),
bank_account char(4),
waiver_needed char(3),
housing_not_needed char(3),
program_created char(8),
created_by varchar(63),
badge_title varchar(255)
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
