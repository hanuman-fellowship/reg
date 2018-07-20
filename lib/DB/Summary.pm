use strict;
use warnings;
package DB::Summary;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS summary;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE summary (
id integer primary key autoincrement,
date_updated text,
time_updated text,
who_updated text,
gate_code text,
registration_location text,
signage text,
orientation text,
wind_up text,
alongside text,
back_to_back text,
leader_name text,
staff_arrival text,
staff_departure text,
leader_housing text,
food_service text,
flowers text,
miscellaneous text,
feedback text,
field_staff_std_setup text,
field_staff_setup text,
sound_setup text,
check_list text,
converted_spaces text,
needs_verification text,
prog_person text,
workshop_schedule text,
workshop_description text,
date_sent text,
time_sent text,
who_sent text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO summary
(date_updated, time_updated, who_updated, gate_code, registration_location, signage, orientation, wind_up, alongside, back_to_back, leader_name, staff_arrival, staff_departure, leader_housing, food_service, flowers, miscellaneous, feedback, field_staff_std_setup, field_staff_setup, sound_setup, check_list, converted_spaces, needs_verification, prog_person, workshop_schedule, workshop_description, date_sent, time_sent, who_sent) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my (@fields) = split /\|/, $line, -1;
        $sth->execute(@fields);
    }
}

1;

__DATA__
20180720|1345|2||reg loc|<p>sig</p>|ori|win|alo|bac|lea nam|sta arr|sta dep|<p>lea hou</p>|<p>cb foo ser</p>|<p>flo</p>|<p>mis</p>|<p>fee</p>|<p>fie sta set</p>|<p>sou set</p>|<p>che</p>|con|yes|mmc arr coo|<p>wor sch</p>|<p>wor des</p>|<p>fie sta sta set</p>|||0
