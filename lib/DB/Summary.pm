use strict;
use warnings;
package DB::Summary;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS summary;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE summary (
    id
    date_updated
    time_updated
    who_updated
    gate_code
    registration_location
    signage
    orientation
    wind_up
    alongside
    back_to_back
    leader_name
    staff_arrival
    staff_departure
    leader_housing
    food_service
    flowers
    miscellaneous
    feedback
    field_staff_std_setup
    field_staff_setup
    sound_setup
    check_list
    converted_spaces
    needs_verification
    prog_person
    workshop_schedule
    workshop_description
    date_sent
    time_sent
    who_sent
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO summary
(id, date_updated, time_updated, who_updated, gate_code, registration_location, signage, orientation, wind_up, alongside, back_to_back, leader_name, staff_arrival, staff_departure, leader_housing, food_service, flowers, miscellaneous, feedback, field_staff_std_setup, field_staff_setup, sound_setup, check_list, converted_spaces, needs_verification, prog_person, workshop_schedule, workshop_description, date_sent, time_sent, who_sent) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
