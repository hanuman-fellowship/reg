use strict;
use warnings;
package DB::Registration;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS registration;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE registration (
    id
    person_id
    program_id
    deposit
    referral
    adsource
    kids
    comment
    confnote
    h_type
    h_name
    carpool
    hascar
    arrived
    cancelled
    date_postmark
    time_postmark
    balance
    date_start
    date_end
    early
    late
    ceu_license
    letter_sent
    status
    nights_taken
    free_prog_taken
    house_id
    cabin_room
    leader_assistant
    pref1
    pref2
    share_first
    share_last
    manual
    work_study
    work_study_comment
    work_study_safety
    rental_before
    rental_after
    transaction_id
    from_where
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
