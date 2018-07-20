use strict;
use warnings;
package DB::Registration;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS registration;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE registration (
id integer primary key autoincrement,
person_id integer,
program_id integer,
deposit text,
referral text,
adsource text,
kids text,
comment text,
confnote text,
h_type text,
h_name text,
carpool text,
hascar text,
arrived text,
cancelled text,
date_postmark text,
time_postmark text,
balance text,
date_start text,
date_end text,
early text,
late text,
ceu_license text,
letter_sent text,
status text,
nights_taken text,
free_prog_taken text,
house_id integer,
cabin_room text,
leader_assistant text,
pref1 text,
pref2 text,
share_first text,
share_last text,
manual text,
work_study text,
work_study_comment text,
work_study_safety text,
rental_before text,
rental_after text,
transaction_id integer,
from_where text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO registration
(id, person_id, program_id, deposit, referral, adsource, kids, comment, confnote, h_type, h_name, carpool, hascar, arrived, cancelled, date_postmark, time_postmark, balance, date_start, date_end, early, late, ceu_license, letter_sent, status, nights_taken, free_prog_taken, house_id, cabin_room, leader_assistant, pref1, pref2, share_first, share_last, manual, work_study, work_study_comment, work_study_safety, rental_before, rental_after, transaction_id, from_where) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
