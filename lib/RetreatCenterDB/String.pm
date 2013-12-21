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

my %doc_for;
sub doc_for {
    if (%doc_for) {
        return \%doc_for;
    }
    seek DATA, 0, 0;
    STRS1:
    while (my $line = <DATA>) {
        last STRS1 if $line eq "__STRINGS__\n";
    }
    my ($key, $doc);
    STRS2:
    while (my $line = <DATA>) {
        chomp $line;
        $line =~ s{'}{\\'}xmsg;
        if ($line =~ m{ \A \s }xms) {
            $doc_for{$key} .= $line;
            next STRS2;
        }
        ($key, $doc) = $line =~ m{ \A (.*?) \s+ - \s+ (.*) \z}xms;
        $doc_for{$key} = $doc;
    }
    return \%doc_for;
}

1;
__DATA__
overview - Strings are the way that Reg keeps its configuration data.
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
cal_abutt_style - line style when drawing abutting events in the calendar
cal_abutt_thickness - line thickness when drawing abutting events in the calendar
cal_arr_color - the color for arrivals in the personal retreat popup in the calendar
cal_day_line - a boolean - do we want a line underneath the day names
    in the calendar - see lib/ActiveCal.pm
cal_day_width - the width of a day in the calendar
cal_event_border - the width of the border for (all) events in the calendar
cal_event_color - the border color for Events in the calendar
cal_fri_sun_color - the color of the column for Fri-Sun in the calendar
cal_lv_color - the color for departures in the personal retreat popup in the calendar
cal_mon_thu_color - the color of the column for Mon-Thu in the calendar
cal_pr_color - the color of the little box at the bottom of each day
    with the number of personal retreats - in the calendar
cal_today_color - the color of 'today' in the calendar - at the top of the current month
center_tent - the display name for the housing type 'center_tent'
center_tent_end - what mmdd are center tents taken down?
center_tent_start - what mmdd are center tents put up?
ceu_lic_fee - how much to charge for issuing a ceu certificate?
click_enlarge - the text to display to tell the user that they can click to enlarge
    a picture of the presenter in a program web page.
commuting - the display name for the housing type 'commuting'
costhdr - the display name for housing cost when there are no extra days in the program
credit_amount - when cancelling a registration in an MMC program this is
    the default amount of credit the person will receive.
credit_nonprog - The name of an extra account that is used only
    for non-program related credit card payments.
credit_nonprog_people - The people to notify if a non-program related credit
    card payment is made.
date_coming_going_printed - obsolete - used to be used for
    knowing when the coming/going listing had been printed - to determine
    what page to present when prog_staff first logs in.  now the coming/going
    page is always shown.
dble - the display name for the housing type 'dble'
dble_bath - the display name for the housing type 'dble_bath'
default_date_format - the format used when doing $dt->format() or when
    a $dt is stringified in a template.
deposit_lines_per_page - number of lines per page when printing a deposit for filing.
disc1days - number of days of housing to qualify for the first discount
disc1pct - percentage for the first housing discount
disc2days - no longer needed - a second housing discount - could revive
disc2pct - no longer needed - a second housing discount - could revive
disc_pr - percentage discount for mid-week PRs
disc_pr_end - the date when mid-week PR discounts end
disc_pr_start - the date when mid-week PR discounts begin
dormitory - the display name for the housing type 'dormitory'
dp_B_color - color for the daily pic - blocks
dp_F_color - color for the daily pic - female
dp_M_color - color for the daily pic - male
dp_R_color - color for the daily pic - rental
dp_S_color - color for the daily pic - meeting Space
dp_X_color - color for the daily pic - mixed gender house
dp_empty_bed_char - the character to use in the daily pic for empty beds.
    it is appended to the character for the gender of the room.
dp_empty_bed_color - the color to use in the daily pic for the empty bed character
dp_img_percent - a percentage to resize the daily pic image - browser specific???
dp_margin_bottom - margin at the bottom of the daily pic
dp_margin_right - margin at the right of the daily pic
dp_resize_block_char - the character to use for blocks that have resized the room
dp_resize_char - the character to use for rooms that have been resized by a lodging.
    it is appended to the character for the gender of the room.
dp_resize_color - the color of the resize character
dp_type1 - 1st type of daily pic - choices: indoors/outdoors/special/resident/future use
dp_type2 - 2nd type of daily pic
dp_type3 - 3rd type of daily pic
dp_type4 - 4th type of daily pic
dp_type5 - 5th type of daily pic
economy - the display name for the housing type 'economy'
email - The display named for the word 'Email' in the generated Rental web pages.
email1 - text to display before a leader's email address in the generated program page
email2 - text to display after a leader's email address in the generated program page
extra_hours_charge - how many $'s to charge per person per hour of extra time for a Rental.
    this is time before 4:00 on the first day and after 1:00 on the ending day.
from - email address that emails are sent From.
from_title - name of the person that emails are From.
ftp_dir - FTP info for mountmadonna.org
ftp_dir2 - FTP info for mountmadonna.org - staging directory
ftp_hfs_dir - FTP info for hanumanfellowship.org - for temple reservations people
ftp_hfs_password - FTP info for hanumanfellowship.org
ftp_hfs_site - FTP info for hanumanfellowship.org
ftp_hfs_user - FTP info for hanumanfellowship.org
ftp_login - FTP info for mountmadonna.org
ftp_mlist_requests - FTP info for mountmadonna.org - for people that made mlist requests
ftp_mmi_dir - FTP info for mountmadonnainstitute.org
ftp_mmi_login - FTP info for mountmadonnainstitute.org
ftp_mmi_passive - FTP info for mountmadonnainstitute.org
ftp_mmi_password - FTP info for mountmadonnainstitute.org
ftp_mmi_site - FTP info for mountmadonnainstitute.org
ftp_mmi_transactions - FTP info for mountmadonnainstitute.org - for online registrations for MMI courses
ftp_omp_dir - The directory on mountmadonna.org for online member payments
ftp_passive - FTP info for mountmadonna.org
ftp_password - FTP info for mountmadonna.org
ftp_rental_dir - FTP info for mountmadonna.org - for rental grid changes
ftp_ride_dir - FTP info for mountmadonna.org - for ride requests
ftp_site - FTP info for mountmadonna.org
ftp_transactions - FTP info for mountmadonna.org - for online registrations for MMC programs.
ftp_userpics - FTP info for mountmadonna.org - for driver pictures - referenced in email to riders
gate_code_cc_email - who to Cc when sending the Tuesday morning gate code email reminder
gate_code_email - who to email when sending the Tuesday morning gate code email reminder
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
