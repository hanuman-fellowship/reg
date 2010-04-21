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
    brdesc
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
    school
    level
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
/);
__PACKAGE__->set_primary_key(qw/id/);

# cancellation policy
__PACKAGE__->belongs_to(canpol => 'RetreatCenterDB::CanPol', 'canpol_id');
# rental - for parallel programs.
__PACKAGE__->belongs_to(rental => 'RetreatCenterDB::Rental', 'rental_id');
# housecost
__PACKAGE__->belongs_to(housecost => 'RetreatCenterDB::HouseCost',
                        'housecost_id');
# summary
__PACKAGE__->belongs_to('summary' => 'RetreatCenterDB::Summary', 'summary_id');
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
            edate    => { '>=',    tt_today($c)->as_d8() },
            webready => 'yes',
        },
        { order_by => [ 'sdate', 'edate' ] },
    );
    #
    # go through the programs in order
    # skipping the unlinked programs
    # setting the prev and next links.
    # and assigning a sequential program number.
    # these are used in subsequent methods.
    #
    my ($prev_prog);
    for my $p (grep { $_->linked } @programs) {
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
    for my $p (reverse @programs) {
        next unless $p->linked;
        my $sd = $p->sdate_obj();
        $first_of_month{$sd->month . $sd->year} = $p;
    }
    @programs;
}
sub web_addr {
    my ($self) = @_;

    my $dir = "http://$string{ftp_site}/";

    return ($self->linked)? "$dir$string{ftp_dir2}/" . $self->fname
          :                 $dir . $self->unlinked_dir             ;
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

sub leader_names {
    my ($self) = @_;

    my $s = "";
    my @leaders = map {
                      my $p = $_->person();
                      $_->just_first()? $p->first()
                      :                 $p->first . " " . $p->last
                  }
                  sort {
                      $a->person->last  cmp $b->person->last or
                      $a->person->first cmp $b->person->first
                  }
                  grep {
                    ! $_->assistant
                  }
                  $self->leaders;
    return "" unless @leaders;
    my $last = pop @leaders;
    $s .= join ", ", @leaders;
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
    if ($ed->month == $sd->month) {
        $dates .= "-" . $ed->day;
    } else {
        $dates .= " - " . $ed->format("%B %e");
    }
    my $extra = $self->extradays;
    if ($extra) {
        $ed += $extra;
        if ($ed->month == $sd->month) {
            $dates .= ", " . $sd->day . "-";
            $dates .= $ed->day;
        } else {
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
    my $s = gptrim($self->webdesc);
    my $barnacles = $self->footnotes;
    if ($barnacles) {
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
#
# generate HTML (yes :() for a fee table)
# ??? _could_ do this in a Template.
#
sub fee_table {
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

    my $fee_table = <<EOH;
<p>
<table>
EOH
    $fee_table .= <<EOH unless $PR;
<tr><th colspan=$cols>$string{heading}</th></tr>
<tr><td colspan=$cols>&nbsp;</td></tr>
EOH
    $fee_table .= "<tr><th align=left valign=bottom>$string{typehdr}</th>";
    if ($extradays) {
        my $plural = ($ndays > 1)? "s": "";
        $fee_table .= "<th align=right width=70>$ndays Day$plural</th>".
                      "<th align=right width=70>$fulldays Days</th></tr>\n";
    } else {
        $fee_table .= "<th align=right>$string{costhdr}</th></tr>\n";
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
        my $cost = $PR? $housecost->$t()
                  :     $self->fees(0, $t);
        next unless $cost;        # this type of housing is not offered at all.
        $fee_table .= "<tr><td>" . $string{"long_$t"} . "</td>";
        $fee_table .= "<td align=right>$cost</td>\n";
        if ($extradays) {
            $fee_table .= "<td align=right>" .
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
        $bio .= "<p>" . gptrim($l->biography);
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
    my $m = $self->sdate_obj->month;
    my $cal = slurp "cal$m";
    $cal;
}
sub nextprog {
    my ($self) = @_;
    $self->{"next"}->fname;
}
sub prevprog {
    my ($self) = @_;
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
#
# this routine can be uncommented to generate a
# popup enlargement.  when we have better pictures, that is.
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
# move the next line up above </table>
#<tr><td align=center colspan=2 class='click_enlarge'>$string{'click_enlarge'}</td></tr>
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
    return gptrim($self->canpol->policy);
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
    return "<input type=checkbox name='email$n' value='$em'>$em_entity<br>";
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
            if ($reg->house_id == 0) {
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

    if (! $self->linked()) {
        $type .= "Unlinked ";
    }
    if ($self->school() != 0) {
        $type .= "MMI ";
    }
    if ($self->rental_id()) {
        $type .= "Hybrid ";
    }
    chop $type;
    $type;
}

sub largest_meeting_place {
    my ($self) = @_;
}

sub color_bg {
    my ($self) = @_;
    return sprintf("#%02x%02x%02x", $self->color() =~ m{(\d+)}g);
}

sub PR {
    my ($self) = @_;
    $self->name() =~ m{personal\s+retreat}i; 
}

1;
