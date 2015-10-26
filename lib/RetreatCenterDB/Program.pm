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
    image
    kayakalpa
    canpol_id
    extradays
    full_tuition
    deposit
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
# level
__PACKAGE__->belongs_to(level => 'RetreatCenterDB::Level',
                        'level_id');
# school
__PACKAGE__->belongs_to(school => 'RetreatCenterDB::School',
                        'school_id');
# summary
__PACKAGE__->belongs_to(summary => 'RetreatCenterDB::Summary', 'summary_id');

# affiliations
__PACKAGE__->has_many(affil_program => 'RetreatCenterDB::AffilProgram',
                      'p_id');
__PACKAGE__->many_to_many(affils => 'affil_program', 'affil',
                          { order_by => 'descrip' },
                         );
# web documents
__PACKAGE__->has_many(documents => 'RetreatCenterDB::ProgramDoc',
                      'program_id');

# registrations
__PACKAGE__->has_many(registrations => 'RetreatCenterDB::Registration',
                      'program_id');
        # ??? how to sort by person names?

# leaders
__PACKAGE__->has_many(leader_program => 'RetreatCenterDB::LeaderProgram',
                      'p_id');
__PACKAGE__->many_to_many(leaders => 'leader_program', 'leader',
                          { order_by => 'l_order' });

# exceptions - maybe
__PACKAGE__->has_many(exceptions => 'RetreatCenterDB::Exception', 'prog_id');

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

#
# we really can't call $self->{field}
# but must call $self->field()
# or just $self->field;
#
# something about when it actually does populate the object...???
#

my $default_template = slurp("default");
my %first_of_month;

# do I really need $c passed in???
sub future_programs {
    my ($class, $c) = @_;
    my @programs = $c->model('RetreatCenterDB::Program')->search(
        {
            edate    => { '>=', tt_today($c)->as_d8() },
            webready => 'yes',
            -or => [
                'school.mmi' => '',           # MMC
                'level.public' => 'yes', # MMI public standalone course
            ],
        },
        { order_by => [ 'sdate', 'edate' ] },
    );
    #
    # go through the programs in order
    # skipping the unlinked and cancelled programs
    # setting the prev and next links.
    # treat MMI programs in a special way - they will never
    # be the target of a prev or next link.
    # assigning a sequential program number.
    # these are used in subsequent methods.
    #
    my ($prev_prog);
    PROG:
    for my $p (@programs) {
        next PROG if ! $p->linked || $p->cancelled || $p->school != 0;
        $p->{prev}   = $prev_prog || $p;
        $prev_prog->{"next"} = $p;
        $prev_prog = $p;
    }
    # set the last program's next
    $prev_prog->{"next"} = $prev_prog;

    #
    # set the first of the month program hash.
    # we go backwards through the programs
    # so the last one overwritten will be the first of the month!
    #
    PROG:
    for my $p (reverse @programs) {
        next PROG if ! $p->linked || $p->cancelled || $p->school != 0;
        my $sd = $p->sdate_obj();
        $first_of_month{$sd->month . $sd->year} = $p;
    }
    @programs;
}

sub web_addr {
    my ($self) = @_;

    my $dir = "http://$string{ftp_site}/";

    return ($self->linked)? "$dir$string{ftp_dir2}/" . $self->fname
          :                 $dir . ($self->unlinked_dir || '')     ;
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
    date($self->edate) || "";
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
    return get_time($self->reg_start());
}
sub end_hour_obj {
    my ($self) = @_;
    return get_time($self->prog_end());
}
sub reg_end_obj {
    my ($self) = @_;
    return get_time($self->reg_end());
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
sub template_src {
    my ($self) = @_;
    return ($self->ptemplate)?  slurp($self->ptemplate)
          :                     $default_template;
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
                   grep { $_->breakout() ne 'yes' }
                   $self->rental_id()? $self->rental->bookings()
                   :                   $self->bookings();
    @bookings? $bookings[0]->meeting_place()->name()
    :          "";
}

sub title1 {
    my ($self) = @_;
    if (my $value = $self->_exception_for('title1')) {
        return $value;
    }
    return ($self->leader_names && $self->leader_names !~ m{\bstaff\b}i)?
                $self->leader_names:
                $self->title;
}
sub title2 {
    my ($self) = @_;
    if (my $value = $self->_exception_for('title2')) {
        return $value;
    }
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

sub leader_names {
    my ($self) = @_;

    if (my $value = $self->_exception_for('leader_names')) {
        return $value;
    }
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

    if (ref($self) =~ /Program/) {
        if (my $value = $self->_exception_for('dates')) {
            return $value;
        }
    }
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
        $s = "<P><STRONG>Credits:</STRONG></P>";
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
sub _exception_for {
    my ($self, $tag) = @_;
    for my $e ($self->exceptions) {
        if ($e->tag eq $tag) {
            return $e->value;
        }
    }
}
#
# generate HTML (yes :() for a fee table)
# ??? _could_ do this in a Template.
#
sub fee_table {
    my ($self) = @_;

    if (my $value = $self->_exception_for('fee_table')) {
        return $value;
    }
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

    # I had trouble getting the proper alignment of various
    # table elements.  When I opened the gen_files/*.html file
    # in Safari it showed proper alignment when I used the
    # align property of the <td> or <th>.   But there was
    # some interaction with the other style sheets that were loaded.
    # So I tried forcing a style on each <td> and <th>.
    # Seems to work so I celebrate.
    #
    my $fee_table = <<EOH;
<p>
<table>
EOH
    if ($dncc) {
        $fee_table .= <<"EOH";
<tr><th colspan=$cols style="text-align: center">
TUITION \$$tuition<br>
plus<br>
MEALS and LODGING FEES:<br>
<br>
Note that because housing availability may vary for the duration<br>
of this program per-day fees are shown below.<br>
<br>
</th></tr>
EOH
    }
    elsif (! $PR) {
        my $heading = ($tuition)?
            "Cost Per Person<br>(including tuition, meals, lodging, and facilities use)"
           :"Cost Per Person<br>(including meals, lodging, and facilities use"
               ." - does NOT include tuition)"
           ;
        $heading = "<center>$heading</center>";
        $fee_table .= "<tr><th colspan=$cols>$heading</th></tr>\n";
        $fee_table .= "<tr><td colspan=$cols>&nbsp;</td></tr>\n";
    }
    $fee_table .= "<tr><th style='text-align: left' valign=bottom>$string{typehdr}</th>";
    if ($extradays) {
        my $plural = ($ndays > 1)? "s": "";
            $fee_table .= "<th style='text-align: right' width=70>$ndays Day$plural</th>".
                          "<th style='text-align: right' width=70>$fulldays Days</th></tr>\n";
    }
    else {
        $fee_table .= "<th style='text-align: right'>$string{costhdr}</th></tr>\n";
    }
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
        $fee_table .= "<tr><td>" . $string{"long_$t"} . "</td>";
        $fee_table .= "<td style='text-align: right'>\$$cost</td>\n";
        if ($extradays) {
            $fee_table .= "<td style='text-align: right'>\$" .
             $self->fees(1, $t) .
             "</td>\n";
        }
        $fee_table .= "</tr>\n";
    }
    $fee_table .= "</table>\n";
    return $fee_table;
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
        $hcost -= 0.10*$hcost  if $ndays >= 7;      # Strings???
        $hcost -= 0.10*$hcost  if $ndays >= 30;     # Strings???
        $hcost = int($hcost);
    }
    return 0 unless $hcost;        # don't offer this housing type if cost is zero
    return $tuition + $hcost;
}

sub firstprog_prevmonth {
    my ($self) = @_;
    return "#" if $self->cancelled;
    my $sd = $self->sdate_obj;
    my $m = $sd->month;
    my $y = $sd->year;
    my $n = 0;
    while (1) {
        --$m;
        if ($m == 0) {
            $m = 12;
            --$y;
        }
        my $x = $first_of_month{"$m$y"};
        return $x->fname if $x;
        last if $n++ > 5;
    }
    return $self->fname;
}

sub firstprog_nextmonth {
    my ($self) = @_;
    return "#" if $self->cancelled;
    my $sd = $self->sdate_obj;
    my $m = $sd->month;
    my $y = $sd->year;
    my $n = 0;
    while (1) {
        ++$m;
        if ($m == 13) {
            $m = 1;
            ++$y;
        }
        my $x = $first_of_month{"$m$y"};
        return $x->fname if $x;
        last if $n++ > 5;
    }
    return $self->fname;
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
sub month_calendar {
    my ($self) = @_;
    my $ym = $self->sdate_obj->format("%Y%m");
    my $cal = slurp "cal$ym";
    $cal;
}
sub nextprog {
    my ($self) = @_;
    return "#" if $self->cancelled;
    $self->{"next"}->fname;
}
sub prevprog {
    my ($self) = @_;
    return "#" if $self->cancelled;
    $self->{prev}->fname;
}

#
# either the leader pic(s) or the program pic
# or nothing
# this is one place where we emit HTML :(
# not sure how to avoid this in the case where
# there IS no pic.
#
# what about clicking on the pic for a large one?
# open in new window easily closed, sized just right.
# have little note saying "click to enlarge"?
# yes, the above used to work okay.   but we removed it.
# there are lines below that can be uncommented to generate a
# popup enlargement.  when we have better pictures, that is.
# take a look at sub gen_popup as well.
#
sub picture {
    my ($self) = @_;

    my $full = $string{imgwidth};
    my $half = $full/2;

    my @leaders = $self->leaders;
    my $nleaders = @leaders;
    # have an array of pictures instead???
    # which gets pushed onto?
    # and take the first two leaders that have images.
    my ($pic1, $pic2) = ("", "");
    if ($nleaders >= 1 && $leaders[0]->image) {
        $pic1 = "lth-" . $leaders[0]->id . ".jpg";
    }
    if ($nleaders >= 2 && $leaders[1]->image) {
        $pic2 = "lth-" . $leaders[1]->id . ".jpg";
    }
    if ($pic2 and ! $pic1) {
        $pic1 = $pic2;
        $pic2 = "";
    }
    if ($self->image) {  # use program pic if present
        $pic1 = "pth-" . $self->id . ".jpg";
        $pic2 = "";
    }
    return "" unless $pic1;          # no image at all

    # first copy the needed pictures to the 'holding area'
    for my $p ($pic1, $pic2) {
        next unless $p;
        if (! -f "root/static/images/$p") {
            $p =~ s{jpg}{gif};      # this modifies $pic1, $pic2
        }
        mkdir "gen_files/pics";
        copy("root/static/images/$p", "gen_files/pics/$p");
        #my $big = $p;
        #$big =~ s{th}{b};
        #copy("root/static/images/$big", "gen_files/pics/$big");
    }
    if ($pic2) {
        my $pic1_html = "<img src='pics/$pic1' width=$half>";
        #$pic1_html = gen_popup($pic1_html, $pic1);
        my $pic2_html = "<img src='pics/$pic2' width=$half>";
        #$pic2_html = gen_popup($pic2_html, $pic2);
        return <<EOH;
<table cellspacing=0>
<tr><td valign=bottom>$pic1_html</td><td valign=bottom>$pic2_html</td></tr>
</table>
EOH
# IF you want two sizes of pictures - you need to
# move the following line up above </table>
#<tr><td align=center colspan=2 class='click_enlarge'>$string{'click_enlarge'}</td></tr>
# and uncomment various other things near here.
    } else {
        my $pic_html = "<img src='pics/$pic1' width=$full>";
        #$pic_html = gen_popup($pic_html, $pic1);
        $pic_html = "<table><tr><td>"
                    . $pic_html
                    . "</td></tr>"
                    #. "<tr><td align=center class='click_enlarge'>"
                    #. $string{click_enlarge}
                    #. "</td></tr>
                    . "</table>";
        return $pic_html;
    }
}
sub cl_picture {
    my ($self) = @_;

    my $full = $string{imgwidth};
    my $half = $full/2;

    my @leaders = $self->leaders;
    my $nleaders = @leaders;
    # have an array of pictures instead???
    # which gets pushed onto?
    # and take the first two leaders that have images.
    my ($pic1, $pic2) = ("", "");
    if ($nleaders >= 1 && $leaders[0]->image) {
        $pic1 = "lth-" . $leaders[0]->id . ".jpg";
    }
    if ($nleaders >= 2 && $leaders[1]->image) {
        $pic2 = "lth-" . $leaders[1]->id . ".jpg";
    }
    if ($pic2 and ! $pic1) {
        $pic1 = $pic2;
        $pic2 = "";
    }
    if ($self->image) {  # use program pic if present
        $pic1 = "pth-" . $self->id . ".jpg";
        $pic2 = "";
    }
    return "" unless $pic1;          # no image at all

    if ($pic2) {
        my $pic1_html = "<img src='http://$string{ftp_site}/live/pics/$pic1' width=$half>";
        my $pic2_html = "<img src='http://$string{ftp_site}/live/pics/$pic2' width=$half>";
        return <<EOH;
<table cellspacing=0>
<tr><td valign=bottom>$pic1_html</td><td valign=bottom>$pic2_html</td></tr>
</table>
EOH
    } else {
        return "<img src='http://$string{ftp_site}/live/pics/$pic1' width=$full>";
    }
}

sub cancellation_policy {
    my ($self) = @_;
    my $s = gptrim($self->canpol->policy);
    $s =~ s{^<p>|</p>$}{}g;     # no paragraphs at all, please.
    $s;
}

sub gen_popup {
    my ($pic_html, $pic) = @_;
    $pic =~ s{th}{b};
    my ($w, $h) = imgsize("gen_files/pics/$pic");
    my $pw = $w + 80;
    my $ph = $h + 70;
    $pic_html = qq!<a target=_blank onclick='window.open("$pic.html","","width=$pw,height=$ph")'>$pic_html</a>!;
    my $fname = "gen_files/$pic.html";
    open my $out, ">", $fname or die "cannot create $fname: $!\n";
    my $copy = slurp("popup");
    # used to have http://www.mountmadonna.org/staging/ in front
    # this is not right - need to rework using Template Toolkit.
    $copy =~ s{<!--\s*T\s+bigpic\s*-->}{<img src="pics/$pic" width=$w height=$h border=0>};
    print {$out} $copy;
    close $out;
    $pic_html;
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

sub image_file {
    my ($self) = @_;
    my $path = "/static/images/pth-" . $self->id;
    (-f "root/$path.jpg")? "$path.jpg": "$path.gif";
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
    return "<input type=checkbox name='email$n' value='$em'> $em_entity<br>";
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
        $type .= "Course ";
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
    $self->name() =~ m{personal\s+retreat}i; 
}

#
# not good to put this HTML and styling in the code
# need to move the <!-- T xxx --> mechanism into the template toolkit
# and all styles to a .css file.  But what about Exceptions?
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

1;
__END__
overview - Programs are MMC (and MMI) sponsored events for which we do registrations of individuals.
    They have many attributes and many relations to other tables.  
allow_dup_regs - Can a person sign up more than once?  Personal Retreats have this field set to 'yes'.
    Other programs could have it set as well.  If not set we prohibit a duplicate registration.
cancelled - boolean - Has this program been cancelled?  Set/Unset via a menu link.
canpol_id - foreign key to canpol
category_id - foreign key to category
cl_template - confirmation letter template file name.  Mostly it is 'default' but can vary.
    It lives in root/static/templates/letter.
collect_total - Should we collect the total amount due when registering online?
color - RGB values for the color of the program in the DailyPic.
commuting - Are people allowed to commute for this program?
confnote - A note that is included in ALL confirmation notes.
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
id - unique id
image - A boolean - do we have an image for the web page of this program?
    Naming conventions lead us to the actual filename.
kayakalpa - Shall we include a note about Kaya Kalpa information in the confirmation letter?
level_id - For MMI programs this indicates the type of course.
   CS YSC1, CS YSC2, ..., Certificate, ... Course
linked - Shall this program's web page be linked to the others?
lunches - An encoded (essentially binary) field describing which days of the program have lunch.
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
unlinked_dir - For unlinked programs (see the linked attribute) this is
    a directory name on www.mountmadonna.org that will contain the program.
url - A web URL containing further information about the program.
webdesc - A long description of the program.
webready - Is this program ready to be published to the web (at least to
    the staging area)? 
