use strict;
use warnings;
package DB::Affil;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS affils;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE affils (
id integer primary key autoincrement,
descrip varchar(255),
system char(3),
selectable char(3)
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO affils
(descrip, system, selectable) 
VALUES
(?, ?, ?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my ($descrip, $system, $selectable) = split /\|/, $line;
        $sth->execute($descrip, $system, $selectable);
    }
}

1;

__DATA__
Programs||yes
Donor||yes
Buddhist Programs||yes
Meditation Programs||yes
Media/Publications||yes
Pathways Newsletter||yes
Productions||yes
Personal Growth||yes
Yoga Teacher Training||yes
Movement Programs||yes
Music Programs||yes
Yoga Programs||yes
Misc. Programs||yes
Phone List||yes
General||yes
Guru Purnima|yes|yes
Resident||yes
Pacific Cultural Center||yes
General Mailing List||yes
MMS Endowment||yes
MMS Graduates||yes
MMS donations||yes
MMS inquiries||yes
Phone Tree||yes
Staff/YSC Alert||yes
Poor Credit||yes
Ayurveda, Herbs & Health||yes
School||yes
Open House||yes
Gateways||yes
Personal Retreats||yes
Women's Programs||yes
Jewish||yes
Men's Programs||yes
Youth||yes
Satsangi's Parents||yes
Temple Donors $100+||yes
Muneesh and Lirio||yes
all temple donors||yes
Open Gate Sangha||yes
Out of USA||yes
Only in reports for email||yes
Community Studies||yes
Alert When Registering|yes|yes
Deceased||yes
Proposal Submitter|yes|yes
MMI Discount||yes
MMI - Ayurveda|yes|yes
MMI - Community Studies|yes|yes
MMI - Yoga|yes|yes
MMI - Consultations||yes
MMI - Massage|yes|yes
Food||yes
PROGRAMS - Ayurveda||yes
PROGRAMS - Art||yes
PROGRAMS - Men's Programs||yes
PROGRAMS - Movement||yes
HFS Member General|yes|
HFS Member Sponsor|yes|
HFS Member Life|yes|
HFS Member Founding Life|yes|
HFS Member Inactive|yes|
HFS Member Lapsed|yes|
HFS Member Contributing Sponsor|yes|
HFS Member Voter|yes|
Temple Guest|yes|yes
Work Study|yes|yes
