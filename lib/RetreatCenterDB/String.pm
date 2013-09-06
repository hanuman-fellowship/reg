use strict;
use warnings;
package RetreatCenterDB::String;

use base qw/DBIx::Class/;

use Util qw/
    d3_to_hex
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('string');
__PACKAGE__->add_columns(qw/
    the_key
    value
/);

__PACKAGE__->set_primary_key('the_key');

sub value_td {
    my ($self) = @_;
    my $k = $self->the_key();
    my $v = defined($self->value())? $self->value()
            :                        ""
            ;
    if ($k =~ m{_color$}) {
        my $color = d3_to_hex($v);
        return <<"EOH";
<td id=color
 width=100 bgcolor=$color
 onclick="window.location.href='/string/update/$k'"
>
EOH
    }
    return "<td>$v</td>";
}

1;
__END__
overview - strings are the way that Reg keeps its configuration data.
    They're just a key-value pair.
    The records are read into an exported global hash (named %string)
    by the Global::init function.
    This function is called (if needed) on login.
the_key - key
value - value
__STRINGS__
% - Definition (for program pages) of continuing education credit for YTT 500.
* - Definition (for program pages) of continuing education credit for nurses.
** - Definition (for program pages) of continuing education credit for nurses
    LMFT's, and LCSW's.
+ - Definition (for program pages) of spiritual practice prerequisite
    for John F. Kennedy University's Graduate School for Holistic Studies.
MRY - Abbreviation for Monterey airport.
MRY_color - color for Monterey airport in Rides listing.
OAK - Abbreviation for Oakland airport.
OAK_color - color for Oakland airport in Rides listing.
OTH - Abbreviation for Other location for ride pick-up.
OTH_color - color for Other location  in Rides listing.
SFO - Abbreviation for San Francisco airport.
SFO_color - color for San Francisco airport in Rides listing.
SJC - Abbreviation for San Jose airport.
SJC_color - color for San Jose airport in Rides listing.
big_imgwidth - size of large picture - for resizing in Util::resize
cal_abutt_color - color used when drawing abutting events in the calendar.
    Also see lib/ActiveCal.pm
cal_abutt_style - line style when drawing abutting events in the calendar.
cal_abutt_thickness - line thickness when drawing abutting events
    in the calendar.
cal_arr_color - doc
cal_day_line - doc
cal_day_width - doc
cal_event_border - doc
cal_event_color - doc
cal_fri_sun_color - doc
cal_lv_color - doc
cal_mon_thu_color - doc
cal_pr_color - doc
cal_today_color - doc
center_tent - doc
center_tent_end - doc
center_tent_start - doc
ceu_lic_fee - doc
click_enlarge - doc
commuting - doc
costhdr - doc
cov_less_color - doc
cov_more_color - doc
cov_okay_color - doc
credit_amount - doc
credit_nonprog - doc
credit_nonprog_people - doc
date_coming_going_printed - doc
dble - doc
dble_bath - doc
default_date_format - doc
deposit_lines_per_page - doc
disc1days - doc
disc1pct - doc
disc2days - doc
disc2pct - doc
disc_pr - doc
disc_pr_end - doc
disc_pr_start - doc
dormitory - doc
dp_B_color - doc
dp_F_color - doc
dp_M_color - doc
dp_R_color - doc
dp_S_color - doc
dp_X_color - doc
dp_empty_bed_char - doc
dp_empty_bed_color - doc
dp_img_percent - doc
dp_margin_bottom - doc
dp_margin_right - doc
dp_resize_block_char - doc
dp_resize_char - doc
dp_resize_color - doc
dp_type1 - doc
dp_type2 - doc
dp_type3 - doc
dp_type4 - doc
dp_type5 - doc
economy - doc
email - doc
email1 - doc
email2 - doc
extra_hours_charge - doc
from - doc
from_title - doc
ftp_dir - doc
ftp_dir2 - doc
ftp_hfs_dir - doc
ftp_hfs_password - doc
ftp_hfs_site - doc
ftp_hfs_user - doc
ftp_login - doc
ftp_mlist_requests - doc
ftp_mmi_dir - doc
ftp_mmi_login - doc
ftp_mmi_passive - doc
ftp_mmi_password - doc
ftp_mmi_site - doc
ftp_mmi_transactions - doc
ftp_passive - doc
ftp_password - doc
ftp_rental_dir - doc
ftp_ride_dir - doc
ftp_site - doc
ftp_transactions - doc
ftp_userpics - doc
gate_code_cc_email - doc
gate_code_email - doc
green_from - doc
green_glnum - doc
green_glnum_mmi - doc
green_name - doc
green_subj - doc
heading - doc
house_alert - doc
house_height - doc
house_let - doc
house_sum_cabin - doc
house_sum_clean - doc
house_sum_foreign - doc
house_sum_occupied - doc
house_sum_perfect_fit - doc
house_sum_reserved - doc
house_width - doc
housing_log - doc
imgwidth - size of small picture - for resizing in Util::resize
kayakalpa_email - doc
kid_disc - doc
last_deposit_date - doc
last_mmi_deposit_date - doc
long_center_tent - doc
long_commuting - doc
long_dble - doc
long_dble_bath - doc
long_dormitory - doc
long_economy - doc
long_not_needed - doc
long_own_tent - doc
long_own_van - doc
long_quad - doc
long_single - doc
long_single_bath - doc
long_triple - doc
long_unknown - doc
lunch_charge - doc
make_up_clean_days - doc
make_up_urgent_days - doc
max_kid_age - doc
max_lodge_opts - doc
max_shuttles - doc
max_tuit_disc - doc
mem_credit_hours - doc
mem_credit_phone - doc
mem_email - doc
mem_gen_amt - doc
mem_life_total - doc
mem_phone - doc
mem_site - doc
mem_spons_semi_year - doc
mem_spons_year - doc
mem_sponsor_nights - doc
mem_team - doc
member_meal_cost - doc
min_kid_age - doc
mmc_reconciling - doc
mmi_discount - doc
mmi_email - doc
mmi_reconciling - doc
not_needed - doc
nyears_forgiven - doc
online_notify - doc
own_tent - doc
own_van - doc
password_security - doc
payment_C - doc
payment_D - doc
payment_O - doc
payment_S - doc
payment_U - doc
personal_template - doc
phone - doc
prog_end - doc
prog_start - doc
quad - doc
reception_email - doc
reg_end - doc
reg_start - doc
rental_done - doc
rental_done_color - doc
rental_due - doc
rental_due_color - doc
rental_end_hour - doc
rental_received - doc
rental_received_color - doc
rental_sent - doc
rental_sent_color - doc
rental_start_hour - doc
rental_tentative - doc
rental_tentative_color - doc
req_mmi_dir - doc
req_mmi_dir_paid - doc
ride_cancel_penalty - doc
ride_email - doc
ride_glnum - doc
seen_lodge_opts - doc
single - doc
single_bath - doc
smtp_auth - doc
smtp_pass - doc
smtp_port - doc
smtp_server - doc
smtp_user - doc
spons_tuit_disc - doc
sum_copy_id - doc
sys_last_config_date - doc
triple - doc
tt_today - doc
typehdr - doc
unknown - doc
website - doc
weburl - doc
