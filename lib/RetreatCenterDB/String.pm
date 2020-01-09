use strict;
use warnings;
package RetreatCenterDB::String;

use base qw/DBIx::Class/;
use HTML::Entities 'encode_entities';

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
    $v = encode_entities($v);        # for <, >, etc.
    if ($k =~ m{_color \z}xms) {
        my $color = d3_to_hex($v);
        return <<"EOH";
<td id=color
 width=100 bgcolor=$color
 onclick="window.location.href='/string/update/$k'"
>
EOH
    }
    elsif ($k =~ m{ _password }xms) {
        return '<td>' . ('*' x length($v)) . '</td>';
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
badge_width - width of badges
badge_height - height of badges
badge_ftop - front top margin of badges
badge_fleft - front left margin of badges
badge_btop - bottom top margin of badges
badge_bleft - bottom left margin of badges
badge_first_font_size - font size of first name
badge_last_font_size - font size of last name
badge_title_font_size - font size of title
breakfast_cost - cost of breakfast - when reserving online
breakfast_cost_5_12 - cost of breakfast for a child (age 5-12)
breakfast_cost_5_12_family - cost of breakfast for a child - family
breakfast_cost_5_12_guest - cost of breakfast for a child - guest
breakfast_cost_family - cost of breakfast - family
breakfast_cost_guest - cost of breakfast - guest
breakfast_daily_max - maximum number of online breakfast meal requests per day
cal_abutt_color - color used when drawing abutting events in the calendar.
    Also see lib/ActiveCal.pm.  This is used only when cal_abutt_style
    is empty.
cal_abutt_style - line style when drawing abutting events in the calendar.
    This string consists of a sequence of the letters rwab - for red,
    white, abutt color, and black.  Any other character is interpreted
    as being black.  These colors are used in sequence to draw the pixels
    in the abutting line of thickness cal_abutt_thickness.
    Also see 'perldoc GD' and search for setStyle.
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
cal_tot_pop_color - the color of the total guest population count at the bottom of the month image
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
curl_command - the command to invoke after Export to mmc
curl_mmi_command - the command to invoke after Export to mmi
date_coming_going_printed - obsolete - used to be used for
    knowing when the coming/going listing had been printed - to determine
    what page to present when prog_staff first logs in.  now the coming/going
    page is always shown.
days_pass_expire - the number of days a new password is active
days_pass_grace - grace period for expiry
dble - the display name for the housing type 'dble'
dble_bath - the display name for the housing type 'dble_bath'
default_date_format - the format used when doing $dt->format() or when
    a $dt is stringified in a template.
default_num_prog_days - when choosing 'Program' how many days
    into the future should we show programs?
deposit_lines_per_page - number of lines per page when printing a deposit for filing.
dinner_cost - cost of dinner - when reserving online
dinner_cost_5_12 - cost of dinner for a child (aged 5-12)
dinner_cost_5_12_family - cost of dinner for a child - family
dinner_cost_5_12_guest - cost of dinner for a child - guest
dinner_cost_guest - cost of dinner when reserving online - guest
dinner_cost_family - cost of dinner when reserving online - family
dinner_daily_max - maximum number of online dinner meal requests per day
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
ftp_calendar_dir - the directory on mmc.org for the public calendar images, index.html
ftp_dir - FTP info for mountmadonna.org
ftp_dir2 - FTP info for mountmadonna.org - staging directory
ftp_export_site - text describing where things were exported
ftp_grid_dir - where to put the rental grid data?
ftp_hfs_dir - FTP info for hanumanfellowship.org - for temple reservations people
ftp_hfs_password - FTP info for hanumanfellowship.org
ftp_hfs_site - FTP info for hanumanfellowship.org
ftp_hfs_user - FTP info for hanumanfellowship.org
ftp_login - FTP info for mountmadonna.org
ftp_gift_cards_dir - FTP info for mountmadonna.org - for gift cards
ftp_meal_requests_dir - FTP info for mountmadonna.org - for meal requests
ftp_mlist_requests - FTP info for mountmadonna.org - for people that made mlist requests
ftp_mmi_dir - FTP info for mountmadonnainstitute.org
ftp_mmi_login - FTP info for mountmadonnainstitute.org
ftp_mmi_passive - FTP info for mountmadonnainstitute.org
ftp_mmi_password - FTP info for mountmadonnainstitute.org
ftp_mmi_site - FTP info for mountmadonnainstitute.org
ftp_mmi_transactions - FTP info for mountmadonnainstitute.org - for online registrations for MMI courses
ftp_notify_dir - where to place the online notify people
ftp_omp_dir - The directory on mountmadonna.org for online member payments
ftp_passive - FTP info for mountmadonna.org
ftp_password - FTP info for mountmadonna.org
ftp_pr_dir - where to put NoPR.txt data
ftp_rental_dir - FTP info for mountmadonna.org - for rental grid changes
ftp_rental_deposit_dir - FTP info for mountmadonna.org - for rental deposit payment
ftp_rental_deposit_dir_paid - FTP info for mountmadonna.org - for rental deposit payments that were paid
ftp_site - FTP info for mountmadonna.org
ftp_transactions - FTP info for mountmadonna.org - for online registrations for MMC programs.
gate_code_cc_email - who to Cc when sending the Tuesday morning gate code email reminder
gate_code_email - who to email when sending the Tuesday morning gate code email reminder
grid_url - the URL for opening up the Web Grid with the rental $code
green_from - when someone makes a donation to the Green Fund - who is the 
    acknowledgment letter from?
green_glnum - the GL Number for Green Fund donations
green_glnum_mmi - the GL Number for Green Fund donations from MMI registrations
green_name - the name of the person acknowledging Green Fund donations
green_subj - the subject of the Green Fun acknowledgment letter
heading - obsolete - can be removed
house_alert - used to alert someone that a person was housed in a specific room
    For example: ~SH1=amita~101=jayanti~
house_height - the height of the house rectangle when drawing the DailyPic and ClusterView
house_let - The width of a letter in a house name - used to calculate
    the width of the entire image in DailyPic and ClusterView.
house_sum_cabin - the 'weight' of a room that is a cabin
house_sum_clean - the 'weight' of a room that needs to be cleaned (negative)
house_sum_foreign - the 'weight' of a room that some other Program/Rental is occupying
house_sum_occupied - the 'weight' of a room that is partially occupied
house_sum_perfect_fit - the 'weight' of a room that is a
    perfect fit for the housing preference
house_sum_reserved - the 'weight' of a room that is reserved
    for the current program/rental
house_width - the width of a bed in a room - used when drawing the DailyPic and ClusterView
housing_log - shall we keep a log of housing activity in 'hlog'?  See lib/HLog.pm
kayakalpa_email - the email address of the Kaya Kalpa person who is
    notified when a massage request comes in - see script/grab_new.
kid_disc - how much of a lodging discount for children?
last_deposit_date - when was the last MMC deposit made?
    filled in automatically.   Must use get_string and put_string to access.
last_mmi_deposit_date - when was the last MMI deposit made?
    filled in automatically.   Must use get_string and put_string to access.
lead_assist_daily_charge - How much do leaders and assistants pay per day?
long_center_tent - for housing type descriptions.  see RetreatCenterDB::Program::fee_table
long_commuting - for housing type descriptions
long_dble - for housing type descriptions
long_dble_bath - for housing type descriptions
long_dormitory - for housing type descriptions
long_economy - for housing type descriptions
long_not_needed - for housing type descriptions
long_own_tent - for housing type descriptions
long_own_van - for housing type descriptions
long_quad - for housing type descriptions
long_single - for housing type descriptions
long_single_bath - for housing type descriptions
long_triple - for housing type descriptions
long_unknown - for housing type descriptions
lunch_charge - obsolete - can be removed.
    rental_lunch_cost instead.  incorporated into housing cost.
lunch_cost - cost of lunch - when reserving online
lunch_cost_5_12 - cost of lunch for a child (aged 5-12)
lunch_cost_5_12_family - cost of lunch for a child - family
lunch_cost_5_12_guest - cost of lunch for a child - guest
lunch_cost_guest - cost of lunch when reserving online - guest
lunch_cost_family - cost of lunch when reserving online - family
lunch_daily_max - maximum number of online lunch meal requests per day
make_up_clean_days - used when presenting the list of available rooms.
    it is the number of days before a room that needs to be cleaned is marked with an 'N'
make_up_urgent_days - for the make up list - for marking rooms as needed urgently
max_days_after_program_ends - the number of days after a program ends when the program becomes uneditable.
max_kid_age - how old can a person be and still be considered a child?
max_lodge_opts - the maximum number of rooms to offer when lodging a registrant
max_rental_desc - the maximum number of characters in a rental web description
max_tuit_disc - maximum tuition discount for Members - no longer used
mem_credit_hours - obsolete - can be removed
mem_credit_phone - obsolete - can be removed
mem_email - the email address of the membership secretary
mem_gen_amt - how much for a General membership?
mem_life_total - total donations to be a Life member
mem_phone - phone number of the membership secretary
mem_site - obsolete - can be removed
mem_spons_semi_year - amount for semi-annual Sponsor membership
mem_spons_year - amount for annual Sponsor membership
mem_sponsor_nights - number of free lodging nights for a Sponsor member
mem_team - obsolete - can be removed
member_meal_cost - obsolete - can be removed
min_kid_age - minimum age of a person before they need to pay (as a child)
mmc_event_alert - who should be notified by email of a new MMC Program/Rental/Event?
mmc_reconciling - who is doing an MMC reconciliation?
mmi_discount - percentage discount for MMI programs - must be requested via an Affiliation
mmi_email - who should be notified when an MMI mailing list request comes in?
mmi_event_alert - who should be notified by email of a new MMI Program?
mmi_reconciling - who is doing an MMI reconciliation?
not_needed - for housing type descriptions
num_pass_fails - how many times in a row can a wrong password be entered?
nyears_forgiven - how many years before an outstanding balance is forgiven?
online_notify - a list of email addresses to notify when
    an online registration happens.  This is different from the
    notify_on_reg column in the Program table.
omp_load_url - for loading the online membership payment data
omp_pay_url - for making online membership payments
own_tent - for housing type descriptions
own_van - for housing type descriptions
password_security - what level of password security? 0, 1, or 2.
payment_C - description of a Check payment
payment_D - description of a Credit Card payment
payment_O - description an Online payment
payment_S - description of a Cash payment
payment_U - a payment is Due
personal_template - the template for a Personal Retreat program -
    it changes as the 'get_away' is offered or not.
phone - the description of a telephone in the row for a rental online
pre_craft - the date before which Reg generated the program web pages
prepay_link - the URL for prepayment requests for MMC
prepay_mmi_link - the URL for prepayment requests for MMI
pr_max_nights - the maximum number of nights for a PR registration
prog_end - the default time of day that a program ends
prog_start - the default time of day that a program starts
program_director - the name of the Program Director - for the contract
quad - for housing type descriptions
reception_email - who should be notified when an MMC mailing list request comes in?
redirect_email - If empty, ALL outgoing email will be sent to these comma separated address(es).
reg_end - the default time of day for program registration to end
reg_start - the default time of day for program registration to begin
registrar_email - the email address of the registrar
rental_arranged_color - the color of an arranged rental
rental_coord_email - the person to notify when a rental deposit is received online
rental_late_in - the penalty for a late indoor rental
rental_late_out - the penalty for a late outdoor rental
rental_deposit_url - the URL for paying the rental deposit
rental_done - description for a rental status of Done
rental_done_color - the color in the calendar of a Done rental
rental_due - description for a rental status of Due
rental_due_color - the color in the calendar of a Due rental
rental_end_hour - the time of day that rentals normally end
rental_lunch_cost - how much do rentals pay for a lunch?
rental_received - description for a rental status
rental_received_color - the color in the calendar of a Received rental
rental_sent - description for a rental status of Sent
rental_sent_color - the color in the calendar of a Sent rental
rental_start_hour - the time of day that rentals normally start
rental_tentative - description for a rental status of Tentative
rental_tentative_color - the color in the calendar of a Tentative rental
req_mmc_dir - the directory on mountmadonna.org where MMC payment requests live
req_mmc_dir_paid - the directory on mountmadonna.org for paid MMC payment requests
req_mmi_dir - the directory on mountmadonnainstitute.org where MMI payment requests live
req_mmi_dir_paid - the directory on mountmadonnainstitute.org for paid MMI payment requests
seen_lodge_opts - what is the size of the &gt;select&lt; list for housing options?
    There can be many more houses in the list but this is what is initially visible.
single - the display name for the housing type 'single'
single_bath - the display name for the housing type 'single with bath'
smtp_auth - the 'auth' field for the SMTP server
smtp_pass - the 'password' field for the SMTP server
smtp_port - the 'port' field for the SMTP server
smtp_server - the 'server' field for the SMTP server
smtp_user - the 'user' field for the SMTP server
spons_tuit_disc - the percentage of discount offered to
    Sponsor members - no longer offered
sum_copy_id - a place to remember the 'copied' summary page.  it is used
    when later pasting the summary.   format: 'timestamp summary_id name'
sum_email_subject - the first part of the subject when emailing a Summary
sum_intro - the text of the introduction when emailing a Summary
sys_cache_timestamp - the time the cache elements were updated in the database
sys_last_config_date - the last date in the config table
triple - the display name for the housing type 'triple'
tt_today - a place to do 'time travel'.  format: 'username mm/dd/yy'
typehdr - the heading for the list of housing types
unknown - the display name for the housing type 'unknown'
url_prefix - the prefix for all URLs in Reg - like https://akash.mountmadonna.org
website - the title for a Rental's website in the online row for the rental
weburl - the web address for a Rental's website in the online row for the rental
