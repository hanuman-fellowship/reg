use strict;
use warnings;
package RetreatCenter::Controller::Configuration;
use base 'Catalyst::Controller';

use lib '../../';
use Util qw/
    stash
    model
    time_travel_class
    tt_today
    slurp
    JON
    read_only
/;
use Date::Simple qw/
    date
    today
/;
use Time::Simple qw/
    get_time
/;
use File::Copy qw/
    copy
/;
use Text::CSV qw/
/;

use Global;
use File::stat;
my $words = "/var/Reg/words";

sub index : Local {
    my ($self, $c) = @_;

    stash($c,
        time_travel_class($c),
        pg_title => "Configuration",
        files_uploaded => $c->flash->{files_uploaded}||'',
        template => "configuration/index.tt2",
    );
}

sub mark_inactive : Local {
    my ($self, $c) = @_;

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    my ($date_last) = $c->request->params->{date_last};
    my $dt = date($date_last);
    if (! $dt) {
        stash($c,
            mess     => "Invalid date: $date_last",
            template => 'listing/error.tt2',
        );
        return;
    }
    my $dt8 = $dt->as_d8();
    my $n = model($c, 'Person')->search({
        inactive => '',
        date_updat => { "<=", $dt8 },
    })->count();
    stash($c,
        date_last => $dt,
        count     => $n,
        template  => 'listing/inactive.tt2',
    );
}

sub mark_inactive_do : Local {
    my ($self, $c, $date_last) = @_;
}

sub counts : Local {
    my ($self, $c) = @_;

    my @classes = map {
                      +{
                          name  => $_,
                          count => scalar(model($c, $_)->search),
                                # scalar context gives the count
                      }
                  }
                  sort
                  @{RetreatCenterDB->classes()};
    stash($c,
        classes  => \@classes,
        template => 'configuration/counts.tt2',
    );
}

sub _get_words {
    my ($file, $aref) = @_;
    open my $in, '<', $file;
    @$aref = <$in>;
    close $in;
    chomp @$aref;
}

sub spellings : Local {
    my ($self, $c, $reg_id) = @_;
    my (@okay, @maybe);
    _get_words("$words/okaywords.txt",  \@okay);
    _get_words("$words/maybewords.txt", \@maybe);
    stash($c,
        reg_id   => $reg_id,
        okay     => \@okay,
        maybe    => \@maybe,
        template => 'configuration/spellings.tt2',
    );
}
sub spellings_do : Local {
    my ($self, $c, $reg_id) = @_;

    my %P = %{ $c->request->params() };
    my (@okay, %not_okay);
    _get_words("$words/okaywords.txt", \@okay);
    for my $k (sort keys %P) {
        my ($type, $w) = $k =~ m{ \A (maybe|okay)_(\S+) \z }xms;
        if ($type eq 'maybe') {
            push @okay, $w;
        }
        else {
            $not_okay{$w} = 1;
        }
    }
    open my $out, '>', "$words/okaywords.txt";
    # need to sort case insensitively
    for my $w (
        map { $_->[0] } 
        sort { $a->[1] cmp $b->[1] }
        map { [ $_, lc $_ ] }
        @okay
    ) {
        print {$out} "$w\n" unless exists $not_okay{$w};
    }
    close $out;
    open my $empty, '>', "$words/maybewords.txt";
    close $empty;
    $c->response->redirect("/registration/view/$reg_id");
}

#
# for updating these few special 'fixed' documents:
#
# Info Sheet.pdf
# Kaya Kalpa Brochure.pdf
# Main Area Map.pdf
# MMC Food.pdf
# MMC Guest Packet.pdf
# Program Guest Confirmation Letter.pdf
# Program Registration Guidelines.pdf
#
sub documents : Local {
    my ($self, $c) = @_;

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    stash($c,
        pg_title => "Documents for Reg",
        template => 'configuration/documents.tt2',
    );
}

# 'our' so we can reference it from elsewhere...
our %file_named = (
    a_info        => 'Info Sheet.pdf',
    b_kaya        => 'Kaya Kalpa Brochure.pdf',
    c_main_map    => 'Main Area Map.pdf',
    d_food        => 'MMC Food.pdf',
    e_packet      => 'MMC Guest Packet.pdf',
    f_rental_conf => 'Program Guest Confirmation Letter.pdf',
    g_rental_reg  => 'Program Registration Guidelines.pdf',
    h_me_guest    => 'Guest-Packet_MountainExperience.pdf',
);

sub documents_do : Local {
    my ($self, $c) = @_;
    my @mess;
    my %uploads;
    for my $k (sort keys %file_named) {
        my $fname = $file_named{$k};
        if (my $upload = $c->request->upload($k)) {
            if ($upload->filename() ne $fname) {
                push @mess, "The file '" . $upload->filename
                          . "' should be named '$fname'."
                          ;
            }
            else {
                $uploads{$fname} = $upload;
            }
        }
    }
    if (@mess) {
        stash($c,
            mess     => join('<br>', @mess),
            template => 'gen_error.tt2',
        );
        return;
    }
    if (%uploads) {
        my $dir = '/var/Reg/documents';
        my $now = get_time();
        my $now_t24 = $now->t24;
        my $today = tt_today($c);
        my $today_d8 = $today->as_d8();
        for my $fname (sort keys %uploads) {
            copy("$dir/$fname", "$dir/$fname-$today_d8-$now_t24");
            $uploads{$fname}->copy_to("$dir/$fname");
            model($c, 'Activity')->create({
                message => "Uploaded document '$fname'",
                ctime   => $now_t24,
                cdate   => $today_d8,
            });
        }
        $c->flash->{files_uploaded} = join('<br>', sort keys %uploads);
    }
    $c->response->redirect('/configuration/index');
}

my $dr_file = "$words/date_ranges.txt";
sub date_ranges : Local {
    my ($self, $c) = @_;

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    my $date_ranges = "";
    if (-f $dr_file) {
        $date_ranges = slurp($dr_file);
    }
    stash($c,
        date_ranges => $date_ranges,
        template => 'configuration/date_ranges.tt2',
    );
}

sub date_ranges_do : Local {
    my ($self, $c) = @_;

    my @lines = grep { /\S/ }   # skip blank lines
                split "\cM\n", $c->request->params->{date_ranges};
    my $mess = "";
    LINE:
    for my $line (@lines) {
        my ($type, $range, $max) = split ' ', $line;
        if (! ($type && $range && $max)) {
            $mess .= "Invalid format: $line<br>";
            next LINE;
        }
        if ($range !~ m{\d{8}[-]\d{8}}xms) {
            $mess .= "Illegal date range: $range<br>";
            next LINE;
        }
        my ($start, $end) = split '-', $range;
        if ($type !~ m{\A ME|PR \z}xms) {
            $mess .= "Illegal type: $type<br>";
        }
        my $st = date($start);
        if (! $st) {
            $mess .= "Illegal date: $start<br>";
        }
        my $en = date($end);
        if (! $en) {
            $mess .= "Illegal date: $end<br>";
        }
        if ($st && $en && $st > $en) {
            $mess .= "Start date $start is after the End date $end<br>";
        }
        if ($max !~ m{\A \d+ \z}xms) {
            $mess .= "Max value is not numeric: $max";
        }
    }
    if ($mess) {
        stash($c,
            mess     => $mess,
            template => 'listing/error.tt2',
        );
        return;
    }
    open my $out, '>', $dr_file;
    print {$out} map { "$_\n" } @lines;
    close $out;
    $c->response->redirect('/configuration/index');
}

my $dir = "/var/Reg/output/export";
mkdir $dir if ! -d $dir;
#my $fname = "mmc_rg_export.zip";
my $fname = "mmc_rg_export.tar";

my $Reg_id_RG_id_mapping = <<'EOM';
1   63  CC 101
2   93  CC 102 Ensuite
3   64  CC 103
4  145  CC 104 Ensuite
12   94  CC 105 ADA
13   89  CC 107
14   95  CC 108 ADA Ensuite
15   65  CC 109
16   90  CC 110 Triple
17   66  CC 111
18   96  CC 112 Ensuite
19   67  CC 113
20   97  CC 114 Ensuite
21   91  CC 115
22   98  CC 116 Ensuite
23   92  CC 117
24   99  CC 118 Ensuite
5   68  CC 201
27   69  CC 202 Triple
6   70  CC 203
28   71  CC 204 Triple
31  100  CC 205
29  101  CC 206 Triple
32  102  CC 207
30  103  CC 208 Triple
25  104  CC 209
26  105  CC 210 Triple
33  106  CC 211
34  110  CC 212 Ensuite
35  107  CC 213
36  111  CC 214 Ensuite
37  108  CC 215
38  112  CC 216 Ensuite
39  109  CC 217
40  113  CC 218 Ensuite
117  152  Oaks Cabin 1
118  153  Oaks Cabin 2
119  154  Oaks Cabin 3
120  155  Oaks Cabin 4
121  156  Oaks Cabin 5
122  157  Oaks Cabin 6
123  158  Oaks Cabin 7
124  159  Oaks Cabin 8
125  160  Oaks Cabin 9
314  195  Ram 1 Whole Cottage
41  114  Ram 1A
42  115  Ram 1B
43  116  Ram 2A
44  117  Ram 2B
45  118  Ram 2C
315  119  Ram 3A
316  120  Ram 3B
7  121  SH 1 Triple
8  122  SH 2 Triple
9  123  SH 3 Triple
10  124  SH 4 Triple
11  125  SH 5 Double
183  196  SH Main
100  129  Tent Madrone 1
105  130  Tent Madrone 2
106  131  Tent Madrone 3
101  132  Tent Madrone 4
107   75  Tent Madrone 5
102   76  Tent Madrone 6
103  149  Tent Madrone 7
108  150  Tent Madrone 8
104  151  Tent Madrone 9
111  148  Tent Madrone A
273  133  Tent Oaks 11
47  134  Tent Oaks 12
48  135  Tent Oaks 13
49  136  Tent Oaks 14
50   88  Tent Oaks 15
78   77  Tent Oaks 16
79   78  Tent Oaks 17
80   81  Tent Oaks 18
51   82  Tent Oaks 19
52   72  Tent Oaks 20
53   73  Tent Oaks 21
54   74  Tent Oaks 22
81   79  Tent Oaks 23
55   80  Tent Oaks 24
56  163  Tent Oaks 25
82  166  Tent Oaks 26
57  167  Tent Oaks 27
83  168  Tent Oaks 28
58  169  Tent Oaks 29
84  170  Tent Oaks 30
85  171  Tent Oaks 31
86  172  Tent Oaks 33
87  173  Tent Oaks 34
61  174  Tent Oaks 36
62  175  Tent Oaks 37
88  176  Tent Oaks 38
63  177  Tent Oaks 39
89  178  Tent Oaks 40
64  179  Tent Oaks 41
65  180  Tent Oaks 42
90  181  Tent Oaks 43
91  182  Tent Oaks 44
66  183  Tent Oaks 45
67  184  Tent Oaks 46
68  185  Tent Oaks 47
92  186  Tent Oaks 48
69  188  Tent Oaks 49
70  187  Tent Oaks 50
71  189  Tent Oaks 51
93  190  Tent Oaks 52
94  191  Tent Oaks 53
72  192  Tent Oaks 54
95  193  Tent Oaks 55
73  194  Tent Oaks 56
99  165  Tent Oaks 64
317 137  Yurt 1
318 143  Yurt 2
EOM
my @prog_headers = qw/
program_id_original
title
description
date_type
date_start
date_end
*organization_id
location
location_address
*contact_email
*contact_phone
*contact_name
categories
price_structure
/;
my @reg_headers = qw/
registration_id_original
*program_id
program_id_original
status
time_submitted
arrive_date
leave_date
room_id
*lodging_id
parent_registration_id_original
country
first_name
alternative-name
last_name
email
phone
gender
address
address-2
city
state
zip
what-is-your-desired-pronouns
newsletter
hfs-affiliate
guest-type
person-notes
flag-person
diet
diet-restrictions
/;
my @trans_headers = qw/
object_type
registration_id_original
trans_date
description
category
charge_amount
credit_amount
status
merch_trans_id
fund_method
is_test
notes
/;

my $country_code = <<'EOS';
Argentina, AR
Aus, AU
Australia, AU
Austria, AT
Belgium, BE
Bermuda, BM
Brasil, BR
Brazil, BR
British Virgin Islands, VG
Bulgaria, BG
Ca, CA
Can, CA
Canada, CA
Chile, CL
China, CN
Colombia, CO
Columbia, CO
Costa Rica, CR
Croatia, HR
Denmark, DK
Deutschland, DE
England, GB
Finland, FI
France, FR
French West Indies
Gbr, GB
Germany, DE
Ghana, GH
Greece, GR
Holland, NL
Hong Kong, HK
Hungary, HU
Iceland, IS
India, IN
Indonesia, ID
Iran, IR
Ireland, IE
Israel, IL
Italia, IT
Italy, IT
Jamaica, JM
Japan, JP
Jordan, JO
Kenya, KE
Korea, KR
Latvia, LV
Ltu, LT
Malaysia, MY
Mexico, MX
Mongolia, MN
Nederland, NL
Nepal, NP
Netherlands, NL
New Zealand, NZ
Nz, NZ
Nigeria
Northern Ireland
Norway, NG
NZ, NZ
P.R.China, CN
Pakistan, PK
Panama, PA
Peru, PE
Philippines, PH
Poland, PL
Portugal, PT
Puerto Rico, PR
Rus, RU
Russia, RU
Saudi Arabia, SA
Scotland, GB
Singapore, SG
Slovakia, SK
South Africa
South Korea, KR
Spain, ES
Sri Lanka, LK
Sweden, SE
Switzerland, CH
Taiwan, TW
Thailand, TH
The Netherlands, NL
Trinidad, TT
Trinidad and Tobago, TT
Turkey, TR
U.S.A., US
Ua, UA
Uae, AE
Uk, GB
United Arab Emirates, AE
United Kingdom, GB
United States, US
Unites States, US
Uruguay, UY
Us, US
Usa, US
Venezuela, VE
Vietnam, VN
W. Indies, TT
EOS
my %country_code_for;
open my $fh, '<', \$country_code;
while (my $line = <$fh>) {
    chomp $line;
    my ($country, $code) = split '\s*,\s*', $line;
    $country_code_for{$country} = $code;
}
use List::Util qw/
    uniq
/;
# RG program category numbers for Reg affil Program ids:
my $cat_nums = <<'EOH';
20: 65 68 # MMC Annual Yoga Retreats
36: 65 68 69 # MMI - Open House
45: 72 # TEMPLE - Temple Donors $100+
48: 72 # TEMPLE - All Temple Donors
54: 62 65 # MMI - Community Studies
63: 65 75 # MMI - Kaya Kalpa
64: 65 69 # MMI - Ayurveda
65: 65 68 # MMI - Yoga
66: 65 69 # MMI - AY Consultations
67: 72 # Temple Guest
71: 65 69 # MMI - AY Conferences
73: 65 68 69 # MMI - AY & Yoga Events
76: 65 69 # MMI - NAMA
77: 65 # MMI - Workshops & Non-Credit Programs
79: 65 69 # MMI - AHC Interest
80: 65 69 # MMI - C-AP Interest
81: 65 69 # MMI - MA Interest
94: 65 69 # MMI - AYT Interest
104: 65 # MMI - Research Symposium
108: 65 68 69 # MMI - IAYT
109: 65 69 # MMI - Ayurveda World
111: 65 68 # MMI - Yoga Conferences
113: 65 # MMC Hosted by MMC
114: 66 # MMC Personal Retreats
134: 65 68 # MMI - Yoga Prenatal Interest
135: 65 68 # MMI - YTT300 Interest
138: 65 68 # MMI - YTT200 Interest
142: 65 68 # MMC Liberation Retreat 2020
145: 32 67 # MMC Mountain Experience
EOH
my %RG_cat_ids_for_Reg_affil_id;
open my $in, '<', \$cat_nums or die "cannot open cat_nums\n";
while (my $line = <$in>) {
    chomp $line;
    $line =~ s{[#].*\z}{}xms;
    my ($id, @nums) = $line =~ m{(\d+)}xmsg;
    $RG_cat_ids_for_Reg_affil_id{$id} = \@nums;
}
close $in;

my $RG_cat_num = <<'EOH';
9 Movement
31 Online
32 Mountain Experience
49 Symposium
62 Community Studies
63 Template
64 Legacy
65 MM Sponsored
66 Personal Retreat
67 Day Program
68 Yoga
69 Ayurveda
70 Meditation
71 Silent
72 Temple
73 Hybrid
74 HFS Event
75 Bodywork
76 Hosted
77 Remote Reg
78 Social Justice
79 SB/NP/K12 Edu
80 Corp/Found
EOH

my %RG_prog_cat_name_for;
open my $RGin, '<', \$RG_cat_num or die "cannot open RG_cat_num\n";
while (my $line = <$RGin>) {
    chomp $line;
    my ($id, $name) = $line =~ m{\A (\d+) [ ] (.*) \z}xmsg;
    $RG_prog_cat_name_for{$id} = $name;
}
close $RGin;
sub cat_names {
    my @nums = @_;
    return join '|',
           map { $RG_prog_cat_name_for{$_} }
           sort { $a <=> $b }
           uniq
           @nums;
}


sub _gender {
    my ($sex) = @_;
    if (! $sex) {
        return 'im-not-sharing-a-room';
    }
    return ($sex eq 'M' or $sex eq 'male'  )? 'male'
          :($sex eq 'F' or $sex eq 'female')? 'female'
          :($sex eq 'T'                    )? 'trans'
          :                                   'im-not-sharing-a-room'
          ;
}

sub _trans_country {
    my ($s) = @_;
    if (! $s) {
        return '';
    }
    $s =~ s{\A \s*|\s* \z}{}xmsg;   # trim spaces
    $s =~ s{(\w+)}{ucfirst lc $1}xmseg;
    return $s;
}

sub block_date_range {
    my ($b) = @_;
    my $sdate = $b->sdate_obj();
    my $edate = $b->edate_obj();
    my $s;
    if ($sdate == $edate) {
        $s = $sdate->format("%b %e");
    }
    elsif ($sdate->month() eq $edate->month()) {
        $s = $sdate->format("%b %e")
             . "-"
             . $edate->day();
    }
    else {
        $s = $sdate->format("%b %e")
           . "-"
           . $edate->format("%b %e")
           ;
    }
    $s =~ s{\s{2,}}{ }xmsg;
    return $s;
}

#
# Note that Program, Rental, Event all have sdate and edate
# attributes.
#
sub show_booking {
    my ($b, $event) = @_;
    my $s = $b->meeting_place->name;
    # what if not the same dates as the program?
    # I presume it is rare.
    if ($b->sdate != $event->sdate
        ||
        $b->edate != $event->edate
    ) {
        $s .= ' (' . $b->date_range . ')';
    }
    if ($b->breakout) {
        $s .= " - Breakout";
    }
    elsif ($b->dorm) {
        $s .= " - Dorm";
    }
    $s =~ s{\s{2,}}{ }xmsg;
    return $s;
}

=comment 

Import Conditions
	Import ONLY those people records that have
    at least one registration, have a name and
    email address, and are Active

DO NOT IMPORT:  Those who have NO REGISTRATIONS
DO NOT IMPORT:  Temple only
DO NOT IMPORT:  Website Subscriber only
DO NOT IMPORT:  Deceased

	Data clean-up prior to import:
		Records using the same email address : 3400
		Records with the same name: 1463

Have a way of generating a test sample - not all
specific ids for rentals and programs
and a limited number of people in the concocted program
 to hold people's names, emails, etc
 the full export will start at a point with 
 a specific last contact date.

 naming conventions:
 prog - program
 reg - registration
 ren - rental
 pay - payment
 cha - charges
 trans - transaction
 part - partial

=cut


sub _gen_csv {
    my ($c, $start) = @_;

    my $reg_id = 0;     # for concocted registrations (rentals)

    my $today_d8 = today()->as_d8();
    #my $start_d8 = date('1989-01-01')->as_d8();
    my $start_d8 = date($start)->as_d8();
    my $N = '';
    my $Z = 0;
    my $veg_no_restrict = "vegetarian-with-no-restrictions";

    my %RG_id_for;
    for my $line (split '\n', $Reg_id_RG_id_mapping) {
        my ($Reg_id, $RG_id) = $line =~ m{\A \s* (\d+) \s+ (\d+)}xms;
        $RG_id_for{$Reg_id} = $RG_id;
    }
    my $csv = Text::CSV->new ({ binary => 1, auto_diag => 1 });
    open my $prog_fh,  '>:encoding(utf8)', "$dir/programs.csv"
        or die "no prog";
    open my $reg_fh,   '>:encoding(utf8)', "$dir/registrations.csv"
        or die "no reg";
    open my $trans_fh, '>:encoding(utf8)', "$dir/transactions.csv"
        or die "no trans";
    open my $report, '>', "$dir/report.txt"
        or die "no report";
    open my $me_list, '>', "$dir/me_list.txt"
        or die "no me_list";
    print {$me_list} "FUTURE Mountain Experience Registrations\n\n";
    open my $vr_list, '>', "$dir/vr_list.txt"
        or die "no vr_list";
    print {$vr_list} "Venues and Rooms for Future Programs\n";
    print {$vr_list} "====================================\n\n";
    my $nvenues = 0;
    my $nblocks = 0;
    my $nrbookings = 0;

    open my $event_list, '>', "$dir/event_list.txt"
        or die "no event_list";
    print {$event_list} "Future Events\n";
    print {$event_list} "=============\n";
    my $nevents = 0;

    $csv->say($prog_fh,  [ grep { ! /\A[*]/ } @prog_headers  ]);
    $csv->say($reg_fh,   [ grep { ! /\A[*]/ } @reg_headers   ]);
    $csv->say($trans_fh, [ grep { ! /\A[*]/ } @trans_headers ]);

    # to help determine where we should start ...
    my %prog_by_year;
    my %reg_by_year;
    my %trans_by_year;

    my $prev_yr = 0;
    my $no_email = 0;
    my $deceased = 0;
    my $inactive = 0;
    my $web_sub_temple = 0;
    my $nprog = 0;
    my $nreg = 0;
    my $npr = 0;
    my $nme = 0;

    # Get affil ids
    my $website_sub_affil_id;
    my ($ws_af) = model($c, 'Affil')->search({
                   descrip => 'Website Subscriber',
               });
    if ($ws_af) {
        $website_sub_affil_id = $ws_af->id;
    }
    else {
        die "No affil for Website Subscriber";
    }

    my $mmc_donor_affil_id;
    my ($m_af) = model($c, 'Affil')->search({
                   descrip => 'MMC Donors',
               });
    if ($m_af) {
        $mmc_donor_affil_id = $m_af->id;
    }
    else {
        die "No affil for MMC Donors";
    }
    my $hfs_donor_affil_id;
    my ($hd_af) = model($c, 'Affil')->search({
                   descrip => 'HFS Donor',
               });
    if ($hd_af) {
        $hfs_donor_affil_id = $hd_af->id;
    }
    else {
        die "No affil for HFS Donor";
    }

    my $alert_affil_id;
    my ($alert_af) = model($c, 'Affil')->search({
                   descrip => 'Alert When Registering',
               });
    if ($alert_af) {
        $alert_affil_id = $alert_af->id;
    }
    else {
        die "No affil for Alert When Registering";
    }

    my %unknown_h_id;       # house ids not in RG

    # make the (mostly empty) program for Personal Retreats
    # where ALL personal retreat and ALL special guest
    # registrations will live.
    # and one for Mountain Experience
    my $pr_sg_prog_id = 9998;
    my $me_prog_id    = 9999;
    $csv->say($prog_fh, [
        $pr_sg_prog_id,         # program_id_original
        "Personal Retreats",    # title
        "Personal Retreats",    # description
        "hotel",                # date type
        $N,                     # date start
        $N,                     # date end
        "Mount Madonna Center", # location
        "445 Summit",           # location address
        #$N,                    # email
        #$N,                    # phone
        #$N,                    # name
        cat_names(66),          # categories (PR category)
        'lodging',              # price_structure
    ]);
    # and one for all Mountain Experience registrations
    $csv->say($prog_fh, [
        $me_prog_id,            # program_id_original
        "Mountain Experience from Reg",  # title
        "Mountain Experience",  # description
        "hotel",                # date type
        $N,                     # date start
        $N,                     # date end
        "Mount Madonna Center", # location
        "445 Summit",           # location address
        #$N,                    # email
        #$N,                    # phone
        #$N                     # name
        cat_names(32,67),       # categories (PR category) + one day
        'special',              # price_structure
    ]);
    PROGRAM:
    for my $prog (
        model($c, 'Program')->search(
            { sdate => { '>=' => $start_d8 } },
            { order_by => 'sdate' }
        )
    ) {
        my $yr = $prog->sdate_obj->year;
        if ($yr != $prev_yr) {
            print "$yr\n";  # progress report to STDOUT
            $prev_yr = $yr;
        }
        print $prog->sdate_obj->format("%F"), "\n";

        # RG Program Category ids
        my @prog_categories = ();
        for my $ap ($prog->affil_program) {
            if (exists $RG_cat_ids_for_Reg_affil_id{$ap->a_id}) {
                push @prog_categories,
                     @{$RG_cat_ids_for_Reg_affil_id{$ap->a_id}};
            }
        }
        # non hybrid programs
        if (! $prog->rental_id) {
            push @prog_categories, 65;      # MM sponsored pricing tier
        }
        if ($prog->rental_id) {
            push @prog_categories, 76;      # rental hybrid program
        }
        # one day programs
        if ($prog->sdate eq $prog->edate) {
            push @prog_categories, 67;
        }
        # onsite or online
        if ($prog->name =~ m{online}xmsi) {
            push @prog_categories, 31;  # online
        }
        # HFS programs
        if ($prog->name =~ m{purnima|jayanti|ratri}xmsi) {
            push @prog_categories, 74;
        }

        my $p_id;
        if ($prog->name =~ m{personal\s+retreat|special\s+guest}xmsi) {
            $p_id = $pr_sg_prog_id;
        }
        else {
            # are there any registrations of people that
            # have an email address?
            #
            my $has_email = 0;
            REG:
            for my $reg ($prog->registrations) {
                if ($reg->person->email) {
                    $has_email = 1;
                    last REG;
                }
            }
            if (! $has_email && $prog->sdate <= $today_d8) {
                # skip empty (no registrations yet) programs in the past.
                # DO add an empty program in the future
                next PROGRAM;
            }

=comment

# maybe??

            my ($email, $phone, $name);
            my @leaders = $prog->leaders;
            if (@leaders) {
                my $lead = $leaders[0];     # use just the first
                my $per = $lead->person;
                $name = $per->name;
                $email = $lead->public_email || $per->email;
                $phone = $per->tel_cell
                         || $per->tel_work
                         || $per->tel_home;
            }

=cut

            # PROGRAM
            my $webdesc = $prog->webdesc || '';
            $webdesc =~ s{[<][^>]*[>]}{}xmsg;
            my ($email, $phone, $name) = ($N, $N, $N);
            my @leaders = $prog->leaders;
            if (@leaders) {
                my $lead = $leaders[0];
                my $per = $lead->person;
                $name = $per->name;
                $email = $lead->public_email || $per->email;
                $phone     = $per->tel_cell
                            || $per->tel_work
                            ||     $per->tel_home;;
            }
            my $price = 'special';
            if (   $prog->housing_not_needed
                && $prog->housing_not_needed eq ''
            ) {
                $price = 'lodging';
            }
            elsif ($prog->donation_tiers
                   && $prog->donation_tiers ne ''
            ) {
                $price = 'sliding-scale';
            }
            $csv->say($prog_fh, [
                $prog->id,                      # program_id_original
                $prog->title,                   # title
                $webdesc,                       # description
                "fixed",                        # date type
                $prog->sdate_obj->format("%F"), # start date
                $prog->edate_obj->format("%F"), # end date
                "Mount Madonna Center",         # location
                "445 Summit",                   # location address
                cat_names(@prog_categories),    # categories
                $price,                         # price_structure
            ]);
            ++$prog_by_year{$prog->sdate_obj->year};
            ++$nprog;
            $p_id = $prog->id;
            if ($prog->sdate >= $today_d8) {
                # a future program
                # record the venues for adding post go-live
                #
                # venues for hybrids are in the rental
                #
                my @bookings = $prog->rental_id? $prog->rental->bookings
                              :                  $prog->bookings;
                my @blocks   = $prog->rental_id? $prog->rental->blocks
                              :                  $prog->blocks;
                if (@bookings || @blocks) {
                    print {$vr_list}
                        $prog->title
                      . ' - ' . $prog->sdate_obj->format("%D")
                      . "\n";
                    if (@bookings) {
                        print {$vr_list} "Venues:\n";
                        for my $b (@bookings) {
                            print {$vr_list} "    "
                                . show_booking($b, $prog) . "\n";
                            ++$nvenues;
                        }
                    }
                    if (@blocks) {
                        print {$vr_list} "Room Blocks:\n";
                        for my $b (@blocks) {
                            my $dates = "";
                            if ($b->sdate != $prog->sdate
                                ||
                                $b->edate != $prog->edate
                            ) {
                                $dates = ' ('
                                       . block_date_range($b)
                                       . ')';
                            }
                            print {$vr_list} "    "
                                           . $b->house->name
                                           . "$dates\n";
                            ++$nblocks;
                        }
                    }
                    print {$vr_list} "\n";
                }
            }
        }
        # Okay, we have a Reg program id
        # to put on the registrations

        REG:
        for my $reg (sort {
                         $a->date_start <=> $b->date_start
                     }
                     $prog->registrations
        ) {
            if ($reg->cancelled) {
                # skip cancelled registrations
                next REG;
            }
            my $per = $reg->person;
            if (!$per) {
                next REG;
            }
            if (! $per->email) {
                ++$no_email;
                next REG;
            }
            if ($per->deceased) {
                ++$deceased;
                next REG;
            }
            if ($per->inactive) {
                ++$inactive;
                next REG;
            }
            my $r_id = $reg->id;
            my $time_submitted = $N;
            if ($reg->date_postmark) {
                $time_submitted = $reg->date_postmark_obj->format("%F")
                                . ' '
                                . ($reg->time_postmark_obj->t12 || '12:00')
                                ;
            }
            my $room_id = 0;
            my $htype = $reg->h_type;
            my $h_id = $reg->house_id;
            if ($h_id) {
                if (exists $RG_id_for{$h_id}) {
                    $room_id = $RG_id_for{$h_id};
                }
                elsif (! exists $unknown_h_id{$h_id}) {
                    $unknown_h_id{$h_id} = 1;
                }
            }
            elsif ($htype eq 'commuting') {
                $room_id = 83;      # RG room 'Commuter 1 - 25p'
                                    #                       50p   ? 85
                                    #                       100p  ? 84
            }
            elsif ($htype eq 'own_van') {
                $room_id = 128;     # Lot CC
                                    # Lot Redwood   ? 127
                                    # Lot SH        ? 147
                                    # Lot Log House ? 146
            }
            elsif ($htype eq 'not needed') {
                $room_id = $N;      # empty string
            }
            # person comment, not Reg comment
            my $comment = $per->comment;
            if ($comment) {
                $comment =~ s{[<][^<]*[>]}{}msg;    # strip tags
                chomp $comment;
            }

            my $country = $N;
            my $s = _trans_country($per->country);
            if ($s) {
                if (exists $country_code_for{$s}) {
                    $country = $country_code_for{$s};
                }
                else {
                    print {$report} "No country code for '$s'\n";
                }
            }

            # What affiliations?
            # does this person have the affiliation 'Website Subscriber'?
            my $website_sub = 'no';
            if (my ($ap) = model($c, 'AffilPerson')->search({
                    p_id => $per->id,
                    a_id => $website_sub_affil_id,
                })
            ) {
                $website_sub = 'yes';
            }
            # HFS Member?
            my $hfs_member = $N;
            my $mem = $per->member;
            if ($mem) {
                my $cat = $mem->category;
                if ($cat =~ m{life}xmsi) {
                    $hfs_member = 'founding-life-life-member';
                }
                elsif ($cat =~ m{sponsor}xmsi) {
                    $hfs_member = 'sponsor';
                }
                elsif ($cat =~ m{general|resident}xmsi) {
                    $hfs_member = 'general-resident-member';
                }
                elsif ($cat =~ m{inactive}xmsi) {
                    $hfs_member = 'inactive-lapsed';
                }
                else {
                    $hfs_member = 'inactive-lapsed';
                }
            }
            # HFS Donor
            if (my ($hda) = model($c, 'AffilPerson')->search({
                    p_id => $per->id,
                    a_id => $hfs_donor_affil_id,
                })
            ) {
                if ($hfs_member) {
                    $hfs_member .= ',';
                }
                $hfs_member .= 'donor';
            }
            # MMC Donors
            if (my ($ma) = model($c, 'AffilPerson')->search({
                    p_id => $per->id,
                    a_id => $mmc_donor_affil_id,
                })
            ) {
                if ($hfs_member !~ m{donor}xms) {
                    if ($hfs_member) {
                        $hfs_member .= ',';
                    }
                    $hfs_member .= 'donor';
                }
            }
            my $flag = $N;
            if (my ($ala) = model($c, 'AffilPerson')->search({
                    p_id => $per->id,
                    a_id => $alert_affil_id,
                })
            ) {
                $flag = 'alt-alert-when-registering';
            }
            #
            # REGISTRATION
            my $prog_id = $p_id;
            if ($reg->mountain_experience) {
                # Only past ones?  Future ones are handled manually.
                if ($reg->date_start >= $today_d8) {
                    # add to the ME report
                    my $cost = 0;
                    for my $p ($reg->payments) {
                        $cost += $p->amount;
                    }
                    print {$me_list} $per->name, "\n";
                    print {$me_list} $reg->date_start_obj->format("%D"), "\n";
                    print {$me_list} $per->tel_cell, "\n";
                    print {$me_list} $per->email, "\n";
                    print {$me_list} $per->addr1, "\n";
                    print {$me_list} $per->addr2, "\n" if $per->addr2;
                    print {$me_list} $per->city, ' ',
                                     $per->st_prov, ' ',
                                     $per->zip_post, "\n";
                    print {$me_list} $per->country, "\n" if $per->country;
                    print {$me_list} "   meals: ", $reg->mountain_experience, "\n";
                    print {$me_list} "activity: ", $reg->activity, "\n";
                    print {$me_list} "children: ", $reg->kids, "\n";
                    print {$me_list} " payment: ", '$', $cost, "\n";
                    print {$me_list} "\n";
                    next REG;
                }
                $prog_id = $me_prog_id;
                ++$nme;
            }
            if ($prog_id == $pr_sg_prog_id) {
                ++$npr;
            }
            my $status = $reg->date_start >= $today_d8? 'reserved': 'checked-out';
            $csv->say($reg_fh, [
                $r_id,              # registration_id_original
                $prog_id,           # program_id_original
                                    # JON no 'program_id' from RG
                                    # it is from Reg - or 9998 or 9999
                                    #                  for PR/SG and ME
                $status,            # status
                $time_submitted,    # time_submitted - include hh:mm
                                    # the timestamp of the deposit
                                    # not just for future
                $reg->date_start_obj->format("%F"), # arrive
                $reg->date_end_obj->format("%F"),   # leave
                $room_id,           # room id (RG mapped - verify!)
                $Z,                 # parent_registration_id_original
                $country,           # country
                $per->first,        # first_name
                $per->sanskrit||$N, # alternative-name
                $per->last,         # last_name
                $per->email,        # email JON include? yes
                $per->tel_cell || $per->tel_home || $per->tel_work, # phone
                _gender($per->sex), # gender
                $per->addr1,        # address 1
                $per->addr2,        # address 2
                $per->city,         # city
                $per->st_prov,      # state
                $per->zip_post,     # zip
                $per->pronouns,     # what-is-your-desired-pronouns
                $website_sub,       # newsletter (Website Subscriber affil?)
                $hfs_member,        # hfs-affiliate
                'participant',      # guest-type
                $comment||$N,       # person-notes
                $flag,              # flag-person
                $veg_no_restrict,   # diet
                $per->diet,         # diet-restrictions
            ]);
# JON
#print $per->name, "\n";
#print "pronouns: " . $per->pronouns . "\n";
#print "HFS: " . $hfs_member . "\n";
#print "flag $flag\n";
#print "comment $comment\n";
#print "newsletter $website_sub\n";
#print "prog_id ", $prog_id, "\n";
#print "ts $time_submitted\n";
#<STDIN>;
            ++$reg_by_year{$reg->date_start_obj->year};
            ++$nreg;

            # no transactions (charge or payment)
            # for registrations in the past
            #
            if ($reg->date_start < $today_d8) {
                next REG;
            }

            # JON - what about slugs for transactions?
            # TRANSACTIONS
            #
            # CHARGES
            for my $cha ($reg->charges()) {
                $csv->say($trans_fh, [
                    'registration', # object type??
                    $r_id,
                    $cha->the_date_obj->format("%F"),
                    $cha->what,      # description
                    'lodging-meals', # category - NOT $cha->type_disp??
                    $cha->amount,    # charge
                    $N,              # credit - 0 or blank??
                    'complete',      # status??
                    $N,              # trans id - do not have
                    $N,              # funding method?? - blank = not a payment
                    $Z, # is test
                    $N, # notes
                ]);
                ++$trans_by_year{$cha->the_date_obj->year};
            }
            # PAYMENTS
            for my $pay ($reg->payments) {
                $csv->say($trans_fh, [
                    'registration', # object type??
                    $r_id,
                    $pay->the_date_obj->format("%F"),
                    $pay->what,     # description
                    'other-payment',# category
                    $N,             # charge - 0 or blank??
                    $pay->amount,   # credit
                    'complete',     # status??
                    $N,             # trans id - do not have
                    'reg-payment',  # fund_method
                    $Z,             # is test
                    $N,             # notes
                ]);
                ++$trans_by_year{$pay->the_date_obj->year};
            }
        }
    }

    my $nrent = 0;
    my $nrent_reg = 0;
    my $nrent_trans = 0;

    print "\nRentals:\n";

    print {$vr_list} "Venues and Rooms for Future Rentals\n";
    print {$vr_list} "===================================\n\n";

    RENTAL:
    for my $ren (
        model($c, 'Rental')->search(
            { sdate => { '>=' => $start_d8 } },
            { order_by => 'sdate' }
        )
    ) {
        if ($ren->cancelled) {
            next RENTAL;
        }
        if ($ren->program_id) {
            next RENTAL;
        }
        print $ren->sdate_obj->format("%D"), "\n";
        my $ren_start = $ren->sdate_obj->format("%F");
        my $ren_end   = $ren->edate_obj->format("%F");
        ++$nrent;
        my $contact = $ren->coordinator() || $ren->contract_signer();
            # this is a Person!
        my ($first, $last, $sanskrit, $email, $phone, $sex,
            $addr1, $addr2, $city, $st_prov, $zip_post, $country, $pronouns)
            = ($N) x 13;
        my $no_contact = 0;
        if ($contact && $contact->first =~ /\S/) {
            $first = $contact->first;
            $last = $contact->last;
            $sanskrit = $contact->sanskrit || $N;
            $email = $contact->email; 
            $phone = $contact->tel_cell
                     || $contact->tel_home
                     || $contact->tel_work;
            $sex = $contact->sex;
            $addr1 = $contact->addr1;
            $addr2 = $contact->addr2;
            $city = $contact->city;
            $st_prov = $contact->st_prov;
            $zip_post = $contact->zip_post;
            $pronouns = $contact->pronouns;
            if ($contact->country
                && exists $country_code_for{$contact->country}
            ) {
                $country = $country_code_for{$contact->country};
            }
        }
        else {
            if ($ren->sdate >= $today_d8) {
                print {$report} "No contact person for "
                                . $ren->name . " $ren_start\n"
            }
            $no_contact = 1;
        }

        my @prog_cats = ();
        push @prog_cats, 76, 77;
        my $tier = $ren->mp_cost_tier;
        push @prog_cats, $tier == 1? 64     # Legacy
                        :$tier == 2? 79     # Small Business / Non-Profit
                        :$tier == 3? 79     # Medium??
                        :            80     # 4 = Corporate / Foundation
                        ;
        
        # PROGRAM (aka RENTAL)
        my $webdesc = $ren->webdesc || '';
        $webdesc =~ s{[<][^>]*[>]}{}xmsg;
        my $title = $ren->title;
        if ($title !~ /\S/) {
            $title = $ren->name_trimmed;
        }
        $csv->say($prog_fh, [
            $ren->id,                       # program_id_original
                                                # dup with Program? it's ok
            $title,                         # title
            $webdesc,                       # description
            "fixed",                        # date type
            $ren_start,                     # start date
            $ren_end,                       # end date
            "Mount Madonna Center",         # location
            "445 Summit",                   # location address
            cat_names(@prog_cats),          # categories
            'lodging',                      # price_structure
        ]);

        # COORDINATOR REGISTRATION as a parent for others
        # (no housing assignment)
        # and for deposit and payments
        ++$reg_id;
        my $coord_reg_id = $reg_id;     # for concocted registrations
                                        # from the grid.
        # The coordinator will have TWO registrations??
        # one as parent/coordinator and one as room occupier
        if (! $no_contact) {
            $csv->say($reg_fh, [
                $reg_id,            # registration_id_original - concocted
                $ren->id,           # program_id_original
                                    # JON no 'program_id' from RG
                                    # it is from Reg - or 9998 or 9999
                                    #                  for PR/SG and ME
                'reserved',         # status
                $N,                 # time_submitted - include hh:mm
                                    # the timestamp of the deposit
                                    # not just for future
                $ren_start,         # arrive
                $ren_end,           # leave
                $Z,                 # room id (RG mapped - verify!)
                $Z,                 # parent_registration_id_original
                $country,           # country
                $first,             # first_name
                $sanskrit,          # alternative-name
                $last,              # last_name
                $email,             # email
                $phone,             # phone
                _gender($sex),      # gender
                $addr1,             # address 1
                $addr2,             # address 2
                $city,              # city
                $st_prov,           # state
                $zip_post,          # zip
                $pronouns,          # what-is-your-desired-pronouns
                                        # JON all $N below okay?
                'no',                   # newsletter (Website Subscriber affil?)
                $N,                     # hfs-affiliate
                'renter',               # guest_type
                $N,                     # person-notes
                $N,                     # flag-person
                $veg_no_restrict,       # diet
                $N,                     # diet-restrictions
            ]);
            ++$nrent_reg;
        }

        if ($no_contact || $ren->sdate < $today_d8) {
            # a past rental
            next RENTAL;    # no grid registrants at all
                            # and no transactions
        }

        # venues for future rentals
        # and rooms and room blocks
        #
        my @r_venues = $ren->bookings(); 
        my @r_blocks   = $ren->blocks();
        my @r_rbookings = $ren->rental_bookings();
        if (@r_venues || @r_blocks || @r_rbookings) {
            print {$vr_list}
                $title
              . ' - ' . $ren->sdate_obj->format("%D")
              . "\n";
            print {$vr_list} "Venues:\n" if @r_venues;
            for my $b (@r_venues) {
                print {$vr_list}
                    "    "
                    . show_booking($b, $ren)
                    . "\n";
                ++$nvenues;
            }
            print {$vr_list} "Room Blocks:\n" if @r_blocks;
            for my $b (@r_blocks) {
                my $dates = "";
                if ($b->sdate != $ren->sdate
                    ||
                    $b->edate != $ren->edate
                ) {
                    $dates = ' ('
                           . block_date_range($b)
                           . ')';
                }
                print {$vr_list} "    " . $b->house->name . "$dates\n";
                ++$nblocks;
            }
            print {$vr_list} "Room Bookings:\n" if @r_rbookings;
            for my $b (@r_rbookings) {
                print {$vr_list} "    " . $b->house->name . "\n";
                ++$nrbookings;
            }
            print {$vr_list} "\n";
        }

        # Charges
        # attribute them all to the registration for the coordinator
        for my $cha ($ren->charges()) {
            $csv->say($trans_fh, [
                'registration',     # object-type
                $coord_reg_id,      # coordinator id
                $cha->the_date_obj->format("%F"),
                $cha->what,     # description
                'program',      # category??
                $cha->amount,   # charge
                $N,             # credit - 0 or blank??
                'complete',     # status
                $N,             # no transaction id
                $N,             # funding method - none as a charge
                $Z,             # is test
                $N,             # notes
            ]);
            ++$nrent_trans;
        }
        # Payments
        for my $pay ($ren->payments()) {
            $csv->say($trans_fh, [
                'registration',     # object-type
                $coord_reg_id,      # coordinator id
                $pay->the_date_obj->format("%F"),
                $N,             # description - none??
                'other-payment',# category
                $N,             # charge - 0 or blank??
                $pay->amount,   # credit
                'complete',     # status
                $N,             # no transaction id
                'reg-payment',  # fund_method
                $Z,             # is test
                $N,             # notes
            ]);
            ++$nrent_trans;
        }
        # The Grid
        for my $g (model($c, 'Grid')->search({ rental_id => $ren->id })) {
            my $room_id = $g->house_id;
            if ($room_id == 1001) {
                $room_id = 128;     # see above
            }
            elsif ($room_id == 1002) {
                $room_id = 83;      # see above
            }
            else {
                if (exists $RG_id_for{$room_id}) {
                    $room_id = $RG_id_for{$room_id};
                }
                elsif (! exists $unknown_h_id{$room_id}) {
                    $room_id = 0;
                    $unknown_h_id{$room_id} = 1;
                }
            }
            my @names = split ' ', $g->name;

            # ?? What about children?  What about two names?
            # ?? Just let it be - in the last name?  Just one cost.
            # ?? Messy.

            my $first = shift @names;
            my $last = "@names";
            my ($email) = $g->notes =~ m{([\w.-]+[@][a-zA-Z0-9.-]+)}xmsi;
            # create a "concocted" 'registration'
            my @days = split ' ', $g->occupancy;
                # use @days below
            my ($arr, $dep) = (0, 0);
            for my $i (0 .. $#days) {
                if ($days[$i] eq '1') {
                    if (! defined $arr) {
                        $arr = $i;
                    }
                    $dep = $i;
                }
            }
            my $start = ($ren->sdate_obj + $arr)->format("%F");
            my $end   = ($ren->sdate_obj + $dep + 1)->format("%F");

            # REGISTRATION (aka grid entry)
            ++$reg_id;
            $csv->say($reg_fh, [
                $reg_id,            # registration_id_original - concocted
                $ren->id,           # program_id_original
                                    # no 'program_id' from RG
                                    # it is from Reg - or 9998 or 9999
                                    #                  for PR/SG and ME
                'reserved',         # status
                $N,                 # time_submitted - include hh:mm
                                    # the timestamp of the deposit
                                    # not just for future
                $start,             # arrive
                $end,               # leave
                $room_id,           # room_id
                $coord_reg_id,      # parent_registration_id_original
                $N,            # country
                $first,        # first_name
                $N,            # alternative-name
                $last,         # last_name
                $email,        # $email include? yes
                $N,            # phone
                $N,            # gender
                $N,            # address 1
                $N,            # address 2
                $N,            # city
                $N,            # state
                $N,            # zip
                $N,            # what-is-your-desired-pronouns
                'no',                   # newsletter (Website Subscriber affil?)
                $N,                     # hfs-affiliate
                'participant',          # guest_type
                $N,                     # person-notes
                $N,                     # flag-person
                $veg_no_restrict,       # diet
                $N,                     # diet-restrictions
            ]);
            ++$nrent_reg;

            # TRANSACTION - CHARGE for the room, not a payment
            my $cost = int($g->cost);
            $csv->say($trans_fh, [
                'registration',  # object-type
                $reg_id,      # NOT the coordinator id - the reg id
                $ren_start,   # okay??
                'room charge',  # description
                'lodging-meals',# category
                $cost,          # charge
                $N,             # credit - 0 or blank??
                'complete',     # status??
                $N,             # no transaction id
                $N,             # funding method - none as a charge
                $Z,             # is test
                $N,             # notes
            ]);
            ++$nrent_trans;
        }
    }

    # EVENTS
    for my $ev (
        model($c, 'Event')->search(
            { sdate => { '>=' => $today_d8 } },   # not $start_d8
            { order_by => 'sdate' }
        )
    ) {
        print {$event_list} "\n";
        print {$event_list} "       Name: " . $ev->name . "\n";
        print {$event_list} "       From: "
                            . $ev->sdate_obj->format("%D") . "\n";
        print {$event_list} "         To: "
                            . $ev->edate_obj->format("%D"). "\n";
        print {$event_list} "Description: " . $ev->descr . "\n"
            if $ev->descr;
        print {$event_list} "    Sponsor: " . $ev->organization->name . "\n";
        if ($ev->max) {
            print {$event_list} "        Max: " . $ev->max . "\n";
        }
        my $indent = ' ' x 13;
        my @blocks = $ev->blocks();
        if (@blocks) {
            print {$event_list} "Room Blocks: \n";
            for my $b (@blocks) {
                my $dates = "";
                if ($b->sdate != $ev->sdate
                    ||
                    $b->edate != $ev->edate
                ) {
                    $dates = ' ('
                           . block_date_range($b)
                           . ')';
                }
                print {$event_list} $indent . $b->house->name . "$dates\n";
            }
        }
        my @bookings = $ev->bookings();
        if (@bookings) {
            print {$event_list} "     Venues: \n";
            for my $b (@bookings) {
                print {$event_list} $indent
                    . show_booking($b, $ev) . "\n";
            }
        }
        ++$nevents;
        print {$event_list} "\n-------------------\n";
    }

    close $prog_fh;
    close $reg_fh;
    close $trans_fh;
    close $me_list;

    print {$vr_list} "\n$nvenues Venues to add\n";
    print {$vr_list} "$nblocks Room Blocks to add\n";
    print {$vr_list} "$nrbookings Room Bookings to add\n";
    close $vr_list;

    print {$event_list} "\n$nevents Events to add\n";
    close $event_list;

    print {$report} "\n";
    print {$report} "Programs by Year:\n";
    for my $k (sort keys %prog_by_year) {
        printf {$report} "%4d  %6d\n", $k, $prog_by_year{$k};
    }
    printf {$report} "      ------\n";
    printf {$report} "      %6d\n", $nprog;

    print {$report} "\n";
    print {$report} "Registrations by Year:\n";
    for my $k (sort keys %reg_by_year) {
        printf {$report} "%4d  %6d\n", $k, $reg_by_year{$k};
    }
    printf {$report} "      ------\n";
    printf {$report} "      %6d\n", $nreg;
    print {$report} "\n";
    printf {$report} "%6d Personal Retreat registrations\n", $npr;
    printf {$report} "%6d Mountain Experience registrations\n", $nme;
    printf {$report} "%6d registrations skipped - no email\n", $no_email;
    printf {$report} "%6d registrations skipped - deceased\n", $deceased;
    printf {$report} "%6d registrations skipped - inactive\n", $inactive;

    print {$report} "\n";
    print {$report} "Transactions by Year:\n";
    for my $k (sort keys %trans_by_year) {
        printf {$report} "%4d  %6d\n", $k, $trans_by_year{$k};
    }

    print {$report} "\n";
    print {$report} "Reg House IDs Unknown in RG:\n";
    for my $h_id (sort { $a <=> $b } keys %unknown_h_id) {
        my $house = model($c, 'House')->find($h_id);
        my $name = '';
        if ($house) {
            $name = $house->name;
        }
        printf {$report} "%4d  %s\n", $h_id, $name;
    }
    print {$report} "\n";
    printf {$report} "%5d rentals\n", $nrent;
    printf {$report} "%5d rental registrations\n", $nrent_reg;
    printf {$report} "%5d rental transactions\n", $nrent_trans;
    close $report;
}

1;
