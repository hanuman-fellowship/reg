use strict;
use warnings;
package RetreatCenterDB::Program;
use base qw/DBIx::Class/;

use lib "..";       # so can do perl -c
use Date::Simple qw/
    date
    today
/;
use Time::Simple qw/
    get_time
/;
use Util qw/
    empty
    slurp
    housing_types
    places
    tt_today
    model
    gptrim
    d3_to_hex
/;
use Global qw/%string/;
use Image::Size;
use File::Copy;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('program');
# Set columns in table
__PACKAGE__->add_columns(qw/
    id
    name
    title
    subtitle
    glnum
    housecost_id
    retreat
    sdate
    edate
    tuition
    confnote
    url
    webdesc
    webready
    kayakalpa
    canpol_id
    extradays
    full_tuition
    deposit
    req_pay
    collect_total
    linked
    unlinked_dir
    ptemplate
    cl_template
    sbath
    single
    economy
    commuting
    footnotes
    reg_start
    reg_end
    prog_start
    prog_end
    reg_count
    lunches
    school_id
    level_id
    max
    notify_on_reg
    summary_id
    rental_id
    do_not_compute_costs
    dncc_why
    color
    allow_dup_regs
    percent_tuition
    refresh_days
    category_id
    facebook_event_id
    not_on_calendar
    tub_swim
    cancelled
    pr_alert
    bank_account
    waiver_needed
    housing_not_needed
    program_created
    created_by
    badge_title
    manual_reg_finance
    children_welcome
/);
__PACKAGE__->set_primary_key(qw/id/);

# cancellation policy
__PACKAGE__->belongs_to(canpol => 'RetreatCenterDB::CanPol', 'canpol_id');

# rental - for parallel programs.
__PACKAGE__->belongs_to(rental => 'RetreatCenterDB::Rental', 'rental_id');

# housecost
__PACKAGE__->belongs_to(housecost => 'RetreatCenterDB::HouseCost',
                        'housecost_id');
# category
__PACKAGE__->belongs_to(category => 'RetreatCenterDB::Category',
                        'category_id');
# school
__PACKAGE__->belongs_to(school => 'RetreatCenterDB::School',
                        'school_id');
# level
__PACKAGE__->belongs_to(level => 'RetreatCenterDB::Level',
                        'level_id');
# summary
__PACKAGE__->belongs_to(summary => 'RetreatCenterDB::Summary', 'summary_id');

# affiliations
__PACKAGE__->has_many(affil_program => 'RetreatCenterDB::AffilProgram',
                      'p_id');
__PACKAGE__->many_to_many(affils => 'affil_program', 'affil',
                          { order_by => 'descrip' },
                         );

# registrations
__PACKAGE__->has_many(registrations => 'RetreatCenterDB::Registration',
                      'program_id');
        # ??? how to sort by person names?

# leaders
__PACKAGE__->has_many(leader_program => 'RetreatCenterDB::LeaderProgram',
                      'p_id');
__PACKAGE__->many_to_many(leaders => 'leader_program', 'leader',
                          { order_by => 'l_order' });

# bookings
__PACKAGE__->has_many(bookings => 'RetreatCenterDB::Booking', 'program_id');

# blocks
__PACKAGE__->has_many(blocks => 'RetreatCenterDB::Block',
                      'program_id',
                      {
                          join     => 'house',
                          prefetch => 'house',
                          order_by => 'house.name',
                      },
                     );
__PACKAGE__->belongs_to(created_by => 'RetreatCenterDB::User',
                        'created_by');

sub future_programs {
    my ($self, $c) = @_;
    return $c->model('RetreatCenterDB::Program')->search(
        {
            edate    => { '>=', tt_today($c)->as_d8() },
            webready => 'yes',
            -or => [
                'school.mmi' => '',      # MMC
                'level.public' => 'yes', # MMI public standalone course
            ],
            cancelled => { '!=' => 'yes' },
        },
        {
            join     => [qw/ school level /],
            order_by => [qw/ sdate  edate /],
        },
    );
}

sub confnote_not_empty {
    my ($self) = @_;
    my $s = $self->confnote();
    $s =~ s{<[^>]*>}{}xmsg;     # remove all html tags
    return ! empty($s);
}

sub web_addr {
    my ($self) = @_;

    my $dir = $self->school->mmi? "https://mountmadonnainstitute.org"
             :                    "https://mountmadonna.org";

    return "$dir/program-page/" . $self->id;
}

#
# a few convenience methods to transform the contents
# of a table column into something easily viewable
# within a template...
#
# ??? memoize these date object creations
# they only happen once and are stored in the object hash ref itself.
#
sub sdate_obj {
    my ($self) = @_;
    date($self->sdate) || "";
}
sub edate_obj {
    my ($self) = @_;
    date($self->edate) || "";
}
#
# to accomodate the end date for extended programs
#
sub edate2 {
    my ($self) = @_;
    my $extra = $self->extradays();
    if ($extra) {
        return (date($self->edate())+$extra)->as_d8();
    }
    else {
        return $self->edate() || "";
    }
}
sub edate2_obj {
    my ($self) = @_;
    my $extra = $self->extradays();
    if ($extra) {
        return date($self->edate())+$extra;
            # looks awkward - why not consolidate???
    }
    else {
        return date($self->edate) || "";
    }
}
sub prog_start_obj {
    my ($self) = @_;
    return get_time($self->prog_start());
}
sub prog_end_obj {
    my ($self) = @_;
    return get_time($self->prog_end());
}
sub reg_start_obj {
    my ($self) = @_;
    return get_time($self->reg_start());
}
# same but different name to match Rental - for Summary listings
sub start_hour_obj {
    my ($self) = @_;
    return get_time($self->prog_start_obj());
}
sub end_hour_obj {
    my ($self) = @_;
    return get_time($self->prog_end());
}
sub reg_end_obj {
    my ($self) = @_;
    return get_time($self->reg_end());
}
sub program_created_obj {
    my ($self) = @_;
    date($self->program_created) || "";
}
sub link {
    my ($self) = @_;
    return "/program/view/" . $self->id;
}
sub event_type {
    return "program";
}
sub fname {
    my ($self) = @_;

    return $self->id . ".html";
    # delete everything below, right?
    # right.  it is obsolete.
    my $sd = $self->sdate_obj;
    my $name =
           substr($self->name,  0, 3) .
           "-" .
           $sd->month .
           "-" .
           $sd->day;
    if (-f "$name.html") {
        # one extra should be enough, yes?
        $name .= "a";
    }
    $name .= ".html";
    if (! $self->linked) {   # ul = unlinked
        $name = "ul_$name";
    }
    $self->{fname} = $name;
    system("touch gen_files/$name");        # tricky!
            # we need the above or else the file will not
            # exist when we do the -f check above.
            # ??? really?   isn't it created immediately after
            # getting it?
    $name;
}

#
# find the largest non-breakout space
#
sub main_meeting_place {
    my ($self) = @_;
        
    # forget a Schwartzian Transform - too few to bother
    my @bookings = sort {
                       $b->meeting_place->max() <=> $a->meeting_place->max()
                   }
                   grep { $_->breakout() ne 'yes' && $_->dorm() ne 'yes' }
                   $self->rental_id()? $self->rental->bookings()
                   :                   $self->bookings();
    @bookings? $bookings[0]->meeting_place()->name()
    :          "";
}

sub title_trimmed {
    my ($self) = @_;
    my $title = $self->title();
    $title =~ s{\A \s* (special\s+guest|personal\s+retreat).*}{$1}xmsi;
    return $title;
}

sub title1 {
    my ($self) = @_;
    return ($self->leader_names && $self->leader_names !~ m{\bstaff\b}i)?
                $self->leader_names:
                $self->title;
}
sub title2 {
    my ($self) = @_;
    if ($self->leader_names && $self->leader_names !~ m{\bstaff\b}i) {
        if ($self->subtitle) {
            $self->title . " - " . $self->subtitle;
        } else {
            $self->title;
        }
    } else {
        $self->subtitle;
    }
}
sub barnacles {
    my ($self) = @_;
    my $b = $self->footnotes;
    $b =~ s/\+/&dagger;/g;
    $b =~ s/%/&sect;/g;
    $b = "<span class='barnacles'><sup>$b</sup></span>" if $b;
    $b;
}
sub title1_barnacles {
    my ($self) = @_;
    return (($self->leader_names or $self->subtitle)?
               "":
               $self->barnacles);
}
sub title2_barnacles {
    my ($self) = @_;
    return (($self->leader_names or $self->subtitle)?
               $self->barnacles:
               "");
}

#
# this does not include assistant names
#
sub leader_names {
    my ($self) = @_;

    my $s = "";
    my @leaders = map {
                      $_->leader_name
                  }
                  grep {
                    ! $_->assistant
                  }
                  $self->leaders;
    return "" unless @leaders;
    my $last = pop @leaders;
    $s .= join ", ", @leaders;
    $s .= ", " if @leaders >= 2;
    $s .= " and " if $s;
    $s .= $last;
    $self->{leader_names} = $s;
}
#
# format sdate to edate in a nice way
#
sub dates {
    my ($self) = @_;

    my $sd = $self->sdate_obj;
    my $ed = $self->edate_obj;
    my $dates = $sd->format("%B %e");
    if ($ed == $sd) {
        ; # the dates are fine already - it is a one day program
    }
    elsif ($ed->month == $sd->month) {
        $dates .= "-" . $ed->day;
    }
    else {
        $dates .= " - " . $ed->format("%B %e");
    }
    my $extra = $self->extradays;
    if ($extra) {
        $ed += $extra;
        if ($ed->month == $sd->month) {
            $dates .= ", " . $sd->day . "-";
            $dates .= $ed->day;
        }
        else {
            $dates .= ", " . $sd->format("%B %e") . " - ";
            $dates .= $ed->format("%B %e");
        }
    }
    $dates;
}

#
#
#
sub dates3 {
    my ($self) = @_;
    my $s = $self->dates();
    $s =~ s{(\w+)}{substr($1, 0, 3)}eg;
    $s =~ s{\s\s+}{ }g;
    $s;
}
#
# same as dates - but without the initial month name
# and any subsequent month name truncated to 3 chars.
#
sub dates_tr {
    my ($self) = @_;
    my $dates = $self->dates;
    my ($init_month) = $dates =~ /^(\w+)/;
    $dates =~ s/$init_month\s*//g;
    $dates =~ s/(\w\w\w)\w+/$1/g;
    $dates =~ s/,\s*/<br>/g;
    $dates;
}
#
# same as dates_tr but without the 3 letter abbreviation
# and no transformation of , to <br>
#
sub dates_tr2 {
    my ($self) = @_;
    my $dates = $self->dates;
    my ($init_month) = $dates =~ /^(\w+)/;
    $dates =~ s/$init_month\s*//g;
    $dates;
}
sub prog_dates_style {
    my ($self) = @_;
    return (($self->leader_names or $self->subtitle)?
               "":
               "style='vertical-align: bottom'");
}
sub webdesc_plus {
    my ($self) = @_;
    gptrim($self->webdesc) . expand_footnotes($self->footnotes);
}
sub long_footnotes {
    my ($self) = @_;
    expand_footnotes($self->footnotes);
}
sub expand_footnotes {
    my $barnacles = shift;
    my $s = "";
    if ($barnacles) {
        $s = "<p><b>Credits:</b></p>";
        $s .= "<ul>\n";
        if ($barnacles =~ /\*\*/) {
            $s .= "<li>$string{'**'}\n";
        } elsif ($barnacles =~ /\*/) {
            $s .= "<li>$string{'*'}\n";
        }
        $s .= "<li>$string{'+'}\n" if $barnacles =~ /\+/;
        $s .= "<li>$string{'%'}\n" if $barnacles =~ /%/;
        $s .= "</ul>\n";
    }
    $s;
}
sub weburl {
    my ($self) = @_;
    my $url = $self->url;
    return "" unless $url;
    return "<p>$string{weburl} <a href='http://$url' target='_blank'>$url</a>.";
}

sub fee_table_hash {
    my ($self) = @_;

    my $housecost = $self->housecost();
    my $sdate = $self->sdate_obj();
    my $month = $sdate->month();
    my $edate = $self->edate_obj();
    my $extradays  = $self->extradays();
    my $ndays = ($edate-$sdate) || 1;        # personal retreats exception
    my $fulldays = $ndays + $extradays;
    my $cols  = ($extradays)? 3: 2;
    my $PR    = $self->PR();
    my $tent  = $self->name() =~ m{tnt}i;
    my $dncc  = $self->do_not_compute_costs();
    my $tuition = $self->tuition();
    my $caption;
    if ($dncc) {
        $caption = <<"EOH";
TUITION \$$tuition<br>
plus<br>
MEALS and LODGING FEES:<br>
<br>
Note that because housing availability may vary for the duration<br>
of this program per-day fees are shown below.
EOH
    }
    elsif (! $PR) {
        $caption = ($tuition)?
            "(including tuition, meals, lodging, and facilities use)"
           :"(including meals, lodging, and facilities use"
               ." - does NOT include tuition)"
           ;
    }
    my @headings;
    push @headings, $string{typehdr};
    if ($extradays) {
        my $plural = ($ndays > 1)? "s": "";
            push @headings, "$ndays Day$plural";
            push @headings, "$fulldays Days";
    }
    else {
        push @headings, $string{costhdr};
    }
    my @fee_rows;
    # the hard coded column names below - another way?
    # somehow get them from HouseCost.pm???
    # I think we need them hardcoded.  To tie 'economy' in program to
    # 'economy' in housing_cost.
    #
    for my $t (reverse housing_types(1)) {
        next if $t eq 'commuting'   && ! $self->commuting;
        next if $t eq 'economy'     && ! $self->economy;
        next if $t eq 'single_bath' && ! $self->sbath;
        next if $t eq 'single'      && ! $self->single;

        next if $t eq 'center_tent' && ! (5 <= $month and $month <= 10)
                                    && ! ($PR || $tent);
                                        # ok for PR's - we don't
                                        # know what month...
        next if $PR and ($t eq 'triple' || $t eq 'dormitory');
        my $cost = $dncc || $PR? $housecost->$t()
                  :              $self->fees(0, $t);
        next unless $cost;        # this type of housing is not offered at all.
        my @row;
        push @row, $string{"long_$t"};
        push @row, "\$$cost";
        if ($extradays) {
            push @row, '$' . $self->fees(1, $t);
        }
        push @fee_rows, \@row;
    }
    return (
        fee_table_caption  => $caption,
        fee_table_headings => \@headings,
        fee_table_rows     => \@fee_rows,
    );
}

#
# fees for a given program, a given type and full/basic
#
sub fees {
    my ($self, $full, $type) = @_;

    $type =~ s{^\s*|\s*$}{}g;    # trim front and back
    my $tuition = $full? $self->full_tuition(): $self->tuition();
    my $housecost = $self->housecost;
    my $ndays = $self->edate_obj - $self->sdate_obj;
    $ndays += $self->extradays if $full;
    my $hcost = $housecost->$type;      # column name is correct, yes?
    if ($housecost->type eq "Per Day") {
        $hcost = $ndays*$hcost;
        # no more 7 day discount
        #$hcost -= 0.10*$hcost  if $ndays >= 7;      # Strings???
        $hcost -= ($string{disc2pct}/100)*$hcost  if $ndays >= $string{disc2days};     # Strings???
        $hcost = int($hcost);
    }
    return 0 unless $hcost;        # don't offer this housing type if cost is zero
    return $tuition + $hcost;
}

sub leader_bio {
    my ($self) = @_;
    my $bio = "";
    for my $l ($self->leaders) {
        my $s = gptrim($l->biography);
        if ($s) {
            $bio .= "<p>" . $s;
        }
        if (my $email = $l->public_email) {
            my $first = $l->person->first;
            my $last  = $l->person->last;
            $bio .= "<p>$string{email1} $first $last $string{email2}"
                   ." <a href='mailto:$email'>$email</a>";
        }
        if (my $url = $l->url) {
            $bio .= "<p>$string{weburl}"
                   ." <a href='http://$url' target='_blank'>$url</a>.";
        }
    }
    return $bio;
}

sub cancellation_policy {
    my ($self) = @_;
    my $s = gptrim($self->canpol->policy);
    $s =~ s{^<p>|</p>$}{}g;     # no paragraphs at all, please.
    $s;
}

# class methods
sub current_date {
    my ($class) = @_;
    return today()->format("%B %e, %Y");    # can't use tt_today() - no $c
}
sub current_year {
    my ($class) = @_;
    return today()->year();                 # can't use tt_today() - no $c
}

sub count {
    my ($self) = @_;
    return scalar($self->reg_count);
}
sub meeting_places {
    my ($self, $breakout) = @_;
    places($self, $breakout);
}
sub ceu_issued {
    my ($self) = @_;
    return $self->footnotes() =~ m{\*};
}
#
# look for an email addresses of the leaders.
# return a list of checkboxes
#
sub email_nameaddr {
    my ($self) = @_;
    my @leaders = $self->leaders();
    my $html = "";
    my $em;
    my $n = 1;
    for my $l (@leaders) { 
        if ($em = $l->public_email) {
            $html .= _em_check($l->name_public_email(), $n++);
        }
        if ($em = $l->person->email()) {
            $html .= _em_check($l->person->name_email(), $n++);
        }
    } 
    $html;
}
sub _em_check {
    my ($em, $n) = @_;
    (my $em_entity = $em) =~ s{<(.*)>}{&lt;$1&gt;};
    return qq!<input type=checkbox name='email$n' value="$em"> $em_entity<br>!;
}

#
# a table of leader names and a note if they're unregistered or unhoused.
#
sub leaders_house {
    my ($self, $c) = @_;
    my $html = "<table>\n";
    for my $l ($self->leaders()) {
        my $person = $l->person;
        my $name = $l->just_first()? $person->first()
                  :                  $person->last . ", " . $person->first
                  ;
        $html .= "<tr>";
        $html .= "<td>"
              .  "<a href=/leader/view/" . $l->id() . ">$name</a>"
              .  (($l->assistant)? " * ": "")
              .  "</td>"
              ;
        # when a program has extra days
        # the leaders will be registered for the full one not the normal.
        #
        my (@reg) = model($c, 'Registration')->search({
            person_id  => $person->id(),
            program_id => $self->id(),
        });
        my $style = "style='font-weight: bold; color: red; margin-left: .4in'";
        if (@reg) {
            my $reg = $reg[0];
            if ($reg->pref1 ne 'not_needed' && $reg->house_id == 0) {
                $html .= "<td colspan=2>"
                      .  "<a $style href=/registration/lodge/"
                      .  $reg->id()
                      .  ">Needs Housing</a>"
                      .  "</td>"
                      ;
            }
        }
        else {
            $html .= "<td colspan=2>"
                  .  "<a $style href=/program/leader_update/"
                  .  $self->id()
                  .  ">Unregistered</a>"
                  .= "</td>";
        }
        $html .= "</tr>\n";
    }
    $html .= "</table>\n";
    $html;
}

sub full_count {
    my ($self) = @_;

    my $count = 0;
    for my $r ($self->registrations()) {
        if (! $r->cancelled()
            && $r->date_end() > $self->edate()
        ) {
            ++$count;
        }
    }
    $count;
}

sub prog_type {
    my ($self) = @_;

    my $type = "";

    if ($self->cancelled) {
        $type = "<span class=red>Cancelled</span> ";
    }
    if ($self->level->public()) {
        $type .= "Public ";
    }
    if ($self->school->mmi()) {
        $type .= "MMI ";
    }
    if (! $self->PR && ! $self->linked()) {
        if ($self->school == 0 || $self->level() eq 'A') {
            $type .= "Unlinked ";
        }
    }
    if ($self->rental_id()) {
        $type .= "Hybrid ";
    }
    if ($self->category->name() ne 'Normal') {
        $type .= "Resident ";
    }
    if ($self->webready) {
        $type .= "<span style='color: green'>w</span> ";
    }
    chop $type;
    $type;
}

sub largest_meeting_place {
    my ($self) = @_;
}

sub color_bg {
    my ($self) = @_;
    return d3_to_hex($self->color());
}

sub PR {
    my ($self) = @_;
    $self->name() =~ m{personal\s+retreat|special\s+guest}i; 
}

#
# not good to put this HTML and styling in the code
# need to move the <!-- T xxx --> mechanism into the template toolkit
# and all styles to a .css file.
# this is a maintenance of legacy software issue...
#
sub reg_link {
    my ($self) = @_;

    if ($self->cancelled) {
        return <<'EOS';
<IMG SRC="/Gif/registration_closed.png" STYLE="padding-top:25px;" ALT="Registration Closed" BORDER="0">
EOS
    }
    else {
        my $id = $self->id;
        return <<"EOS";
<A HREF="http://www.mountmadonna.org/cgi-bin/reg1?test=1&id=$id"><IMG SRC="/Gif/register_button.png" ALT="Register for this program" BORDER="0"></A>
EOS
    }
}

sub Bank_account {
    my ($self) = @_;
    my $b = $self->bank_account();
    return $b eq 'mmi'? 'MMI'
          :$b eq 'mmc'? 'MMC'
          :             'Both MMC and MMI'
          ;
}

1;
__END__
overview - Programs are MMC (and MMI) sponsored events for which we do registrations of individuals.
    They have many attributes and many relations to other tables.  
allow_dup_regs - Can a person sign up more than once?  Personal Retreats have this field set to 'yes'.
    Other programs could have it set as well.  If not set we prohibit a duplicate registration.
badge_title - A short description of the program for badges.
bank_account - Where do registrations payments go?  To the MMI bank account ('mmi'), the MMC bank account ('mmc'), or both accounts ('both')?
cancelled - boolean - Has this program been cancelled?  Set/Unset via a menu link.
canpol_id - foreign key to canpol
category_id - foreign key to category
children_welcome - Are children welcome to attend with parents?
cl_template - confirmation letter template file name.  Mostly it is 'default' but can vary.
    It lives in root/static/templates/letter.
collect_total - Should we collect the total amount due when registering online?
color - RGB values for the color of the program in the DailyPic.
commuting - Are people allowed to commute for this program?
confnote - A note that is included in ALL confirmation notes.
created_by - the user who created the program - foreign key to user
deposit - the amount required to deposit when registering.
dncc_why - an obsolete field
do_not_compute_costs - Should we not compute the costs of this program?
economy - Is Economy housing available?
edate - end date of the program
extradays - How many extra days after the end date for the extended version
    of this program?
facebook_event_id - an id referencing the event on facebook.  not a foreign key.
footnotes - A field containing *, **, +, or % - denoting what kind of CEU credits
    are available for this program.  Rather cryptic!  This was inherited directly from
    old reg.
full_tuition - For extended programs what is the tuition for the full length?
glnum - General Ledger number for this program for accounting purposes.
    This is computed based on the start date.
housecost_id - foreign key to housecost
housing_not_needed - No housing is needed for this program - perhaps it is
    being held away from MMC?
id - unique id
kayakalpa - Shall we include a note about Kaya Kalpa information in the confirmation letter?
level_id - For MMI programs this indicates the type of course.
   CS YSC1, CS YSC2, ..., Certificate, ... Course
linked - Shall this program's web page be linked to the others?
lunches - An encoded (essentially binary) field describing which days of the program have lunch.
manual_reg_finance - registrations will initially have manual finance not automatic
max - What is the expected maximum registrations for the program?
name - A name for the program - used internally for identification.
not_on_calendar - Should this program not be included on the calendar?
    Default no (meaning yes include).
notify_on_reg - A list of email addresses to email when people register for the program.
percent_tuition - What percentage of the tuition should be collected
    when someone registers online?  Default is 0.   This would be in addition
    to the specified deposit.
pr_alert - This program has an effect on PRs.  This column contains
    text to 'pop up' when a person registers for a PR whose dates
    overlap with this program's dates.
prog_end - Time the program ends on the last day.
prog_start - Time the program begins on the first day.
program_created - date the program was created
ptemplate - the template file to be used for generating the program web page.
    Defaults to default.tt2 in root/static/templates/web.
refresh_days - a binary encoded field to indicate which days that
    the rooms should be refreshed (new linen).  Mostly for programs longer
    than a week.  It is used when creating the 'make up' list.
reg_count - The number of current registrants.
    This field keeps changing as people sign up and cancel.
    Too difficult and time consuming to keep recomputing it.
reg_end - Time that registration ends on the first day.
reg_start - Time that registration begins on the first day.
rental_id - foreign key to rental - if the program is a 'hybrid'.
req_pay - Do registrations for this program allow requested payments?
retreat - Is this an MMC yoga retreat?
sbath - Are singles with bath allowed?
school_id - foreign key to school
sdate - start date of the program.
single - Are singles allowed for this program?
subtitle - A secondary description of the program.  For the web page.
summary_id - foreign key to summary
tub_swim - should we mention the hot tub and lake swimming in the conf letter?
title - A short description of the program for the web page.
tuition - A charge for the program - mostly for the presenter.
unlinked_dir - Obsolete.  For unlinked programs (see the linked attribute)
    this is a directory name on www.mountmadonna.org that
    will contain the program.
url - A web URL containing further information about the program.
waiver_needed - Registrants for this program must sign a waiver.
webdesc - A long description of the program.
webready - Is this program ready to be Exported?
