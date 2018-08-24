use strict;
use warnings;
package DB::Program;
use DBH;

sub order { 1 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS program;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE program (
id $pk,
name varchar(255) $sdn,
title varchar(255) $sdn,
subtitle varchar(255) $sdn,
glnum varchar(15) $sdn,
housecost_id integer $idn,
retreat char(3) $sdn,
sdate char(8) $sdn,
edate char(8) $sdn,
tuition smallint $idn,
confnote varchar(1023) $sdn,
url varchar(255) $sdn,
webdesc varchar(1023) $sdn,
webready char(3) $sdn,
image varchar(255) $sdn,
kayakalpa char(3) $sdn,
canpol_id integer $idn,
extradays tinyint $idn,
full_tuition smallint $idn,
deposit smallint $idn,
req_pay char(3) $sdn,
collect_total char(3) $sdn,
linked char(3) $sdn,
unlinked_dir varchar(255) $sdn,
ptemplate varchar(255) $sdn,
cl_template varchar(255) $sdn,
sbath char(3) $sdn,
single char(3) $sdn,
economy char(3) $sdn,
commuting char(3) $sdn,
footnotes varchar(255) $sdn,
reg_start char(4) $sdn,
reg_end char(4) $sdn,
prog_start char(4) $sdn,
prog_end char(4) $sdn,
reg_count smallint $idn,
lunches varchar(255) $sdn,
school_id integer $idn,
level_id integer $idn,
max smallint $idn,
notify_on_reg varchar(255) $sdn,
summary_id integer $idn,
rental_id integer $idn,
do_not_compute_costs char(3) $sdn,
dncc_why varchar(255) $sdn,
color char(15) $sdn,
allow_dup_regs char(3) $sdn,
percent_tuition tinyint $idn,
refresh_days varchar(255) $sdn,
category_id integer $idn,
facebook_event_id integer $idn,
not_on_calendar char(3) $sdn,
tub_swim char(3) $sdn,
cancelled char(3) $sdn,
pr_alert varchar(255) $sdn,
bank_account char(4) $sdn,
waiver_needed char(3) $sdn,
housing_not_needed char(3) $sdn,
program_created char(8) $sdn,
created_by varchar(63) $sdn,
badge_title varchar(255) $sdn
)
EOS
}

sub init {
    return;     # not yet
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO program
(id, name, title, subtitle, glnum, housecost_id, retreat, sdate, edate, tuition, confnote, url, webdesc, webready, image, kayakalpa, canpol_id, extradays, full_tuition, deposit, req_pay, collect_total, linked, unlinked_dir, ptemplate, cl_template, sbath, single, economy, commuting, footnotes, reg_start, reg_end, prog_start, prog_end, reg_count, lunches, school_id, level_id, max, notify_on_reg, summary_id, rental_id, do_not_compute_costs, dncc_why, color, allow_dup_regs, percent_tuition, refresh_days, category_id, facebook_event_id, not_on_calendar, tub_swim, cancelled, pr_alert, bank_account, waiver_needed, housing_not_needed, program_created, created_by, badge_title) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my (@fields) = split /\|/, $line, -1;
        $sth->execute(@fields);
    }
}

1;

__DATA__
10|MMC Template|template|||1||20151001|20151003|0|<p><br mce_bogus="1"></p>||<p><br mce_bogus="1"></p>|||yes|1|0|0|100||||default|default|yes|yes||yes||1600|1900|1900|1300|0||1|1|0||999|0||<p><br mce_bogus="1"></p>|||||1|||yes|||mmc|||||0|
