use strict;
use warnings;
package DB::String;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS string;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE string (
    the_key VARCHAR(30),
    value   VARCHAR(200)
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO string
(the_key, value) 
VALUES
(?, ?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my ($key, $val) = split /\|/, $line;
        $sth->execute($key, $val);
    }
}

1;

__DATA__
%|Qualifies for YTT 500. You must <a href="/ytt/ytt500.html">apply to the YTT 500 program</a> before taking this class for credit.
*|Continuing Education Credit for nurses.
**|Continuing Education Credit for nurses, LMFT's, and LCSW's.
+|Fulfills the spiritual practice prerequisite for John F. Kennedy University's Graduate School for Holistic Studies.  
MRY|Monterey
MRY_color|128,128,128
OAK|Oakland
OAK_color|128,128,128
OTH|Other
OTH_color|218, 128, 128
SFO|San Francisco
SFO_color|128, 198, 128
SJC|San Jose
SJC_color|128, 128, 218
badge_bleft|4.9
badge_btop|10
badge_first_font_size|28
badge_fleft|6
badge_ftop|10
badge_height|3.375
badge_last_font_size|16
badge_title_font_size|14
badge_width|2.125
big_imgwidth|600 
cal_abutt_color|0,0,0
cal_abutt_style|
cal_abutt_thickness|5
cal_arr_color|30,255,30
cal_day_line|1
cal_day_width|35
cal_event_border|2
cal_event_color|175, 100, 255
cal_fri_sun_color|255,240,240
cal_lv_color|255,30,30
cal_mon_thu_color|240,240,255
cal_pr_color|130,150,200
cal_today_color|130,200,150
cal_tot_pop_color|175, 210, 153
center_tent|Center Tent
center_tent_end|1031
center_tent_start|0424
ceu_lic_fee|10
click_enlarge|(click to enlarge)
commuting|Commuting
costhdr|Cost
credit_amount|50
credit_nonprog|Credit Cards - Non Program related
credit_nonprog_people|Lila, Richard and Chenli
date_coming_going_printed|20090603
days_pass_expire|60
days_pass_grace|2
dble|Double
dble_bath|Double w/ Bath
default_date_format|%b %e '%q
deposit_lines_per_page|5
disc1days|9999
disc1pct|10
disc2days|30
disc2pct|10
disc_pr|23
disc_pr_end|20160930
disc_pr_start|20160401
dormitory|Dormitory
dp_B_color|255,0,0
dp_F_color|255,0,0
dp_M_color|255,0,0
dp_R_color|255,0,0
dp_S_color|255,0,0
dp_X_color|255,0,0
dp_empty_bed_char|.
dp_empty_bed_color|0,0,0
dp_img_percent|120
dp_margin_bottom|25
dp_margin_right|50
dp_resize_block_char|/
dp_resize_char||
dp_resize_color|255, 185, 255
dp_type1|indoors
dp_type2|outdoors
dp_type3|special
dp_type4|resident
dp_type5|future use
economy|Economy
email|Email
email1|You can contact
email2|at
extra_hours_charge|2
from|reservations@mountmadonna.org
from_title|MOUNT MADONNA CENTER Programs Office
ftp_calendar_dir|calendar
ftp_dir|www
ftp_dir2|staging
ftp_export_dir|www/cgi-bin/export
ftp_export_passive|0
ftp_export_password|Ashtanga!
ftp_export_site|www.mountmadonna.org
ftp_export_user|mmc
ftp_grid_dir|/for_reg/rental
ftp_hfs_dir|ftp/temple_visitors
ftp_hfs_password|&ok^A^qHQk4d0a@11dY6NIE
ftp_hfs_site|temple.mountmadonna.org
ftp_hfs_user|reg
ftp_login|reg
ftp_mlist_requests|/for_reg/mlist_requests
ftp_mmi_dir|/home/mmi/public_html/courses
ftp_mmi_login|reg
ftp_mmi_passive|0
ftp_mmi_password|S1tarAm!
ftp_mmi_site|www.mountmadonnainstitute.org
ftp_mmi_transactions|/for_reg/transactions
ftp_notify_dir|.
ftp_omp_dir|/for_reg/omp_dir
ftp_passive|0
ftp_password|S1tarAm!
ftp_pr_dir|pr
ftp_rental_deposit_dir|/for_reg/rental_deposit
ftp_rental_deposit_dir_paid|/for_reg/rental_deposit/paid
ftp_rental_dir|/for_reg/rental/ftp_dir
ftp_ride_dir|obsolete...
ftp_site|mountmadonna.org
ftp_transactions|/for_reg/transactions
ftp_userpics|/www/userpics
gate_code_cc_email|jon@suecenter.org
gate_code_email|jon@suecenter.org
green_from|jon@suecenter.org
green_glnum|00004
green_glnum_mmi|00005
green_name|Sustainability Council
green_subj|Green Scene
grid_url|http://mountmadonna.org/cgi-bin/grid
heading|Total Cost Per Person<br>(including tuition, meals, lodging, and facilities use)
house_alert|~OH 3=Jivanti~114B=Sahadev~
house_height|20
house_let|10
house_sum_cabin|20
house_sum_clean|-2
house_sum_foreign|-20
house_sum_occupied|10
house_sum_perfect_fit|5 
house_sum_reserved|15
house_width|8.75
housing_log|1
imgwidth|170
kayakalpa_email|jon@suecenter.org
kid_disc|50
last_deposit_date|20180401
last_mmi_deposit_date|20120301
long_center_tent|Mount Madonna Center Tent
long_commuting|Commuting (Day use, meals &amp; facilities)
long_dble|Double (2 to a room or cabin)
long_dble_bath|Double with Bath (2 to a room)
long_dormitory|Dormitory (4-7 to a room)
long_economy|Economy (8 or more to a room)
long_not_needed|Not Needed
long_own_tent|Own Tent
long_own_van|Own Van
long_quad|Quadruple (4 to a room)
long_single|Single (1 to a room or cabin)
long_single_bath|Single with Bath (1 to a room)
long_triple|Triple (3 to a room)
long_unknown|Unknown
lunch_charge|9
make_up_clean_days|2
make_up_urgent_days|4
max_kid_age|12
max_lodge_opts|0
max_rental_desc|20
max_shuttles|10
max_tuit_disc|125
mem_credit_hours|M-F 9-5, Sat 11-5, and Sun 1-7
mem_credit_phone|408-847-0406
mem_email|memberships@mountmadonna.org
mem_gen_amt|50
mem_life_total|12,000
mem_phone|408-847-0406 x334
mem_site|http://hanumanfellowship.org/index.php?option=com_content&task=view&id=249&Itemid=74
mem_spons_semi_year|300
mem_spons_year|600
mem_sponsor_nights|12
mem_team|Shyama Friedberg (Secretary), Lori March
member_meal_cost|14
min_kid_age|2
mmc_event_alert|jon@suecenter.org
mmc_reconciling|0
mmi_discount|20
mmi_email|jon@suecenter.org
mmi_event_alert|jonb@logicalpoetry.com
mmi_reconciling|0
not_needed|Not Needed
num_pass_fails|3
nyears_forgiven|5
omp_load_url|https://mmc.cosmicdev.com/cgi-bin/omp_load
omp_pay_url|https://mmc.cosmicdev.com/cgi-bin/omp
online_notify|jonb@logicalpoetry.com, jon@suecenter.org
own_tent|Own Tent
own_van|Own Van
pal_11_color|145, 255, 255
pal_12_color|255, 255, 255
pal_13_color|255, 255, 255
pal_14_color|255, 255, 255
pal_15_color|255, 255, 255
pal_16_color|255, 255, 255
pal_21_color|255, 255, 255
pal_22_color|255, 255, 255
pal_23_color|255, 255, 255
pal_24_color|255, 255, 255
pal_25_color|255, 255, 255
pal_26_color|255, 255, 255
pal_31_color|255, 255, 255
pal_32_color|255, 255, 255
pal_33_color|80, 95, 255
pal_34_color|255, 255, 255
pal_35_color|255, 255, 255
pal_36_color|255, 255, 255
pal_41_color|255, 255, 255
pal_42_color|255, 255, 255
pal_43_color|255, 255, 255
pal_44_color|255, 255, 255
pal_45_color|255, 255, 255
pal_46_color|255, 255, 255
pal_51_color|255, 255, 255
pal_52_color|255, 255, 255
pal_53_color|255, 255, 255
pal_54_color|255, 255, 255
pal_55_color|255, 255, 255
pal_56_color|255, 255, 255
pal_61_color|255, 255, 255
pal_62_color|255, 255, 255
pal_63_color|255, 255, 255
pal_64_color|255, 255, 255
pal_65_color|255, 255, 255
pal_66_color|255, 255, 255
password_security|2
payment_C|Check
payment_D|Credit
payment_O|Online
payment_S|Cash
payment_U|Due
personal_template|personal_getaway
phone|Phone
pr_max_nights|14
prog_end|1:00 pm
prog_start|7:00 pm
program_director|Vishwamitra David Prisk
quad|Quad
reception_email|jon@suecenter.org
reg_end|7:00 pm
reg_start|4:00 pm
registrar_email|regis@gmail.com
rental_arranged_color|155, 220, 170
rental_coord_email|jon@suecenter.org
rental_done|Done
rental_done_color|255,0,255
rental_due|Due
rental_due_color|200,200,200
rental_end_hour|1:00 pm
rental_late_in|10
rental_late_out|5
rental_lunch_cost|12
rental_received|Received
rental_received_color|0,255,0
rental_sent|Sent
rental_sent_color|160,160,255
rental_start_hour|4:00 pm
rental_tentative|Tentative
rental_tentative_color|255,0,0
req_mmc_dir|/for_reg/req_mmc_dir
req_mmc_dir_paid|/for_reg/req_mmc_dir/paid
req_mmi_dir|/for_reg/req_mmi_dir
req_mmi_dir_paid|/for_reg/req_mmi_dir/paid
ride_cancel_penalty|35
ride_email|transportation@mountmadonna.org
ride_glnum|00025
seen_lodge_opts|8
single|Single
single_bath|Single w/ Bath
smtp_auth|LOGIN
smtp_pass|ABCdef108
smtp_port|50
smtp_server|mail.suecenter.org
smtp_user|test@suecenter.org
spons_tuit_disc|30
sum_copy_id|
sum_email_subject|Logistic plan for
sum_intro|Please review the logistic plan below and then respond with any updates in a different color.
sys_last_config_date|20200901
triple|Triple
tt_today|brajesh 3/4/5
typehdr|Housing Type
unknown|Unknown
url_prefix|http://localhost:3000
website|Website
weburl|For more information see
