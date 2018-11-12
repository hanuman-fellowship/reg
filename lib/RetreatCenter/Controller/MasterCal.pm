use strict;
use warnings;

package RetreatCenter::Controller::MasterCal;
use base 'Exporter';
use lib '../..';
our @EXPORT_OK = qw/
    do_mastercal
/;
use Date::Simple qw/
    date
    days_in_month
    today
/;
use Time::Simple qw/
    get_time
/;
use Util qw/
    trim
    empty
    model
    places
    tt_today
    stash
    reserved_clusters
    avail_mps
    error
    get_now
    check_makeup_new
    check_makeup_vacate
    d3_to_hex
/;
use HLog;
use GD;
use ActiveCal;
use DateRange;      # imports overlap
use Global qw/
    %string
/;
use Net::FTP;

sub do_mastercal {
    my ($self, $c, $the_start, $the_end) = @_;

    my $staff = $c->check_user_roles('prog_staff');
    my $public = $c->user->username() eq 'calendar';
    my $day_width  = $string{cal_day_width};
    my $event_border = $string{cal_event_border};
    my @month_name = qw/
        Jan Feb Mar
        Apr May Jun
        Jul Aug Sep
        Oct Nov Dec
    /;
    my $cancelled = " <span style='background-color: pink'>Cancelled</span>";

    Global->init($c);

    my $std_prog_arr = get_time($string{reg_start});
    my $std_prog_lv  = get_time($string{prog_end});
    my $std_rental_arr = get_time($string{rental_start_hour});
    my $std_rental_lv  = get_time($string{rental_end_hour});

    my $start_param = trim($c->request->params->{start}) || "";
    if (!$start_param) {
        $start_param = $the_start;
    }
    my $start;
    if ($start_param) {
        if (my ($m, $y) = $start_param =~ m{^(\d+)\D+(\d+)$}g) {
            # month year
            $start_param = "$m/1/$y";
        }
        my $dt = date($start_param);
        if ($dt) {
            $start = $dt;
        }
        else {
            # if error - default to today
            #
            $start = tt_today($c);
        }
    }
    else {
        #
        # we want the first of the previous month from 'today'.
        # and 5 months hence.
        #
        $start = tt_today($c);
        my $y = $start->year();
        my $m = $start->month();
        --$m;
        if ($m == 0) {
            $m = 12;
            --$y;
        }
        $start = date($y, $m, 1);
        $the_end = 5;
    }
    $start_param = $start->format("%D");
    my $start_year = $start->year;
    my $start_month = $start->month;
    my $min_ym = sprintf("%4d%02d", $start_year, $start_month);
    my $the_first = sprintf("%4d%02d%02d", $start_year, $start_month, 1);

    # optional end date - otherwise it goes to the last happening date
    # unless, that is, we have a the_end method parameter
    my $end_param = trim($c->request->params->{end}) || "";
    if (!$end_param && $the_end) {
        $end_param = $the_end;
    }
    my @opt_end = ();
    my $ym_param;
    if ($end_param) {
        # n months???
        my $end_date;
        if (my ($m, $y) = $end_param =~ m{^(\d+)\D+(\d+)$}g) {
            # month year
            $y += 2000 if $y < 1900;
            $end_date = date($y, $m, 1);
        }
        elsif ($end_param =~ m{^(\d{1,2})$}) {
            # end_param is how many months to show in total
            # it does not include something like 040109
            #
            # find the ending month/year.
            my $em = $start_month;
            my $ey = $start_year;
            my $nmonths = $end_param;
            while (--$nmonths) {
                ++$em;
                if ($em > 12) {
                    $em = 1;
                    ++$ey;
                }
            }
            $end_date = date($ey, $em, days_in_month($ey, $em));
        }
        else {
            # end_param is the last date
            $end_date = date($end_param);
        }
        if (! $end_date || $end_date < $start) {
            # incorrect syntax/bad value
            $end_date = $start;
        }
        $end_param = $end_date->format("%D");
        $ym_param = $end_date->format("%Y%m");
        if ($end_date) {
            @opt_end = (sdate => { '<=', $end_date->as_d8() });
        }
    }
    # for non-public calendars
    #
    my $go_form = <<"EOH";
<style type="text/css">
\@media print {
    .noprint {
        display: none;
    }
}
</style>
<div class=noprint>
<form action='/event/mastercal' name=form>
<span class=datefld>Images <input type=checkbox name=images checked onclick='image_toggle()'></span>
<span class=datefld>All Details <input type=checkbox name=detail onclick='detail_toggle(0)'></span>
<span class=datefld>Start</span> <input type=text name=start size=10 value='$start_param'>
<span class=datefld>End</span> <input type=text name=end size=10 value='$end_param'>
<span class=datefld><input class=go type=submit value="Go"></span>
&nbsp;&nbsp;
<a href="javascript:popup('/static/help/calendar.html', 620);">How?</a>
&nbsp;&nbsp;
<a href="javascript:popup('/event/cal_colors', 670);">Colors?</a>
&nbsp;&nbsp;
<span style="font-size: 15pt; color: red">Master Calendar</span>
</form>
</div>
<p>
EOH

    my @events;
    for my $ev_kind (qw/Event Program Rental/) {
        my @prog_opt = ();
        my @join_opt = ();
        if ($ev_kind eq "Program") {
            @prog_opt = (
                'level.long_term' => '',    # no long term events
                'me.name'       => { -not_like, "%personal%retreat%" },
                not_on_calendar => '',
            );
            @join_opt = (
                join => [qw/ level /],
            );
        }
        push @events, model($c, $ev_kind)->search({
                          edate => { '>=', $the_first },
                          @opt_end,
                          @prog_opt,
                      }, {
                          @join_opt,
                      });
    }

    my $max_edate = $the_first;
    for my $e (@events) {
        if ($e->edate > $max_edate) {
            $max_edate = $e->edate;
        }
    }
    $max_edate = date($max_edate);

    my $end_year  = $max_edate->year;
    my $end_month = $max_edate->month;
    my $max_ym = sprintf("%4d%02d", $end_year, $end_month);
    if ($ym_param) {
        # don't try to go to an 'extra' month
        $max_ym = $ym_param;
    }

    my %cals;       # a hash of ActiveCal objects indexed by yearmonth
    my %cal_days;   # a hash (indexed by yearmonth) of an array_ref of days
    my %imgmaps;    # the image maps for each calendar image
    my %details;    # for the printable version
    #
    # initialize the cals and imgmaps
    #
    my $year = $start_year;
    my $month = $start_month;
    while ($year < $end_year || ($year == $end_year && $month <= $end_month)) {
        my $key = sprintf("%04d%02d", $year, $month);
        $cals{$key}  = ActiveCal->new($year, $month, \@events, 0, 1);
        for my $d (1 .. days_in_month($year, $month)) {
            $cal_days{$key}[$d] = [];
        }
                # the second dimension is the row - initially undefined
        $imgmaps{$key} = "";
        $details{$key} = "";
        ++$month;
        if ($month > 12) {
            $month = 1;
            ++$year;
        }

    }
    #
    # prepare color numbers for MMC, MMI
    #
    my ($org) = model($c, 'Organization')->search({
                    name => { like => '%MMC Programs%' },
                });
    my @mmc_colors = $org->color =~ m{(\d+)}xmsg;
    ($org) = model($c, 'Organization')->search({
                 name => { like => '%MMI%' },
             });
    my @mmi_colors = $org->color =~ m{(\d+)}xmsg;

    #
    # sort the events by start date so that
    # later ones will be below earlier ones.
    #
    EVENT:
    for my $ev (sort { $a->sdate <=> $b->sdate } @events) {
        my $ev_type = ref($ev);
        $ev_type =~ s{.*::}{};
        $ev_type = lc $ev_type;
        my $ev_type_id = "$ev_type\_id";

        if ($ev_type eq 'program'
            && ($ev->rental_id() || $ev->category->name() ne 'Normal')
        ) {
            # this is a program with a parallel Rental
            # OR a Residental program (YSC, YSL, ...)
            #
            # we _could_ have filtered out the programs with
            # a parallel rental much earlier.  Was there a reason
            # that we didn't?   We prohibit the scheduling of
            # meeting places on the Program side so @places
            # _will_ be empty.
            #
            next EVENT;     # skip it entirely
        }

        # draw on the right image(s)
        #
        my $ev_sdate = $ev->sdate_obj();
        my $ev_edate = $ev->edate_obj();

        my ($full_begins, $ndays_in_normal, $normal_end_day);

        if ($ev_type eq 'program') {
            # are there extra days?
            # draw a little dotted line on the day
            # when the full extension begins (or equivalently
            # when the normal length program ends).
            if ($ev->extradays) {
                $full_begins = $ev->edate_obj;
                $ndays_in_normal = $ev->edate_obj - $ev->sdate_obj;
                $normal_end_day = $ev->edate_obj->day;
                $ev_edate = $ev->edate_obj + $ev->extradays;
            }
        }
        my $event_name = $ev->name();
        $event_name =~ s{ \d?\d/\d\d\s* \z }{}xms;
                                            # tidy up ending mm/yy or m/yy
                                            # not really needed
        $event_name =~ s{ \A MMI-? }{}xms;   # tidy up the front of MMI programs

        my $ev_count = $ev->count();
        my $count = $ev_count;
        my $max = $ev->max();

        #
        # is the program/rental arriving earlier or leaving later
        # than the standard times?  We need to display this in
        # various ways.   So simple to ask for, so complex to actually do!
        #
        my $arr_lv = "";
        my $arr_lv_longer = "";
        if ($ev_type eq "program") {
            if ($ev->reg_start_obj() != $std_prog_arr) {
                $arr_lv = "A" . $ev->reg_start_obj->t12(1);
                $arr_lv_longer = $ev->reg_start_obj->ampm();
            }
            $arr_lv_longer .= "/";
            if ($ev->prog_end_obj() != $std_prog_lv) {
                $arr_lv .= " " if $arr_lv;
                $arr_lv .= "L" . $ev->prog_end_obj->t12(1);
                $arr_lv_longer .= $ev->prog_end_obj->ampm();
            }
        }
        elsif ($ev_type eq "rental") {
            if ($ev->start_hour_obj() != $std_rental_arr) {
                $arr_lv = "A" . $ev->start_hour_obj->t12(1);
                $arr_lv_longer = $ev->start_hour_obj->ampm();
            }
            $arr_lv_longer .= "/";
            if ($ev->end_hour_obj() != $std_rental_lv) {
                $arr_lv .= " " if $arr_lv;
                $arr_lv .= "L" . $ev->end_hour_obj->t12(1);
                $arr_lv_longer .= $ev->end_hour_obj->ampm();
            }
        }
        if ($arr_lv_longer eq "/") {
            $arr_lv_longer = "";
        }
        if ($arr_lv) {
            $arr_lv = " $arr_lv";
        }

        #
        # try to accomodate all three types of happenings.
        # some with mandatory maximums some without.
        #
        if (length $max) {
            if (length $count) {
                $count .= "/$max";
            }
            else {
                $count = $max;
            }
        }
        my $ev_id = $ev->id;

        # find the calendars that we need to draw on
        # for the current event.
        #
        for my $key (ActiveCal->keys($ev_sdate, $ev_edate)) {
            my $cal = $cals{$key};
            if (! $cal) {
                # this event apparently begins in a prior month
                # and overlaps into the first shown month???
                # like today is April 10th and the event is from
                # March 29th to April 4th.
                $cal = $cals{$start->format("%Y%m")};
            }
            my $dr = overlap(DateRange->new($ev_sdate, $ev_edate), $cal);
            my $im = $cal->image;
            my $black = $cal->black;
            my $white = $cal->white;
            my $color = $white;     # for the inside of the rectangle - what else?
            if ($ev_type eq 'event') {
                $color = $im->colorAllocate(
                             $ev->organization->color =~ m{\d+}g,
                         );
            }
            elsif ($ev->name =~ m{MMI}) {       # not $event_name
                $color = $im->colorAllocate(    # it has had MMI- stripped
                             @mmi_colors,
                         );
            }
            else {
                # rentals and MMC programs
                $color = $im->colorAllocate(
                             @mmc_colors,
                         );
            }

            # the horizontal offset
            #
            my $x1 = ($dr->sdate->day-1) * $day_width;
            my $x2 = $dr->edate->day * $day_width;
            
            # what is the VERTICAL offset in the calendar for this event?
            # It depends on what else is there already.
            # We need to keep track of days of the month and also rows
            # in each calendar.
            #
            my $cal_row = 0;
            CAL_ROW:
            while (1) {
                for my $d ($dr->sdate->day .. $dr->edate->day) {
                    if (defined $cal_days{$key}[$d][$cal_row]) {
                        ++$cal_row;
                        next CAL_ROW;
                    }
                }
                last CAL_ROW;
            }
            # so the event will be drawn at $cal_row
            # mark each day in that row as used.
            for my $d ($dr->sdate->day .. $dr->edate->day) {
                $cal_days{$key}[$d][$cal_row] = 1;
            }
            my $y1 = ($cal_row+1) * 40 + 2;
                    # +1 to skip the day number and abbreviated day name
                    # +2 so the thick border does not impede the top line
            my $y2 = $y1 + 20;

            # what to display in the overlib popup?
            #
            my $disp = $event_name;
            if ($ev->cancelled) {
                $disp .= $cancelled;
            }
            if (length $count) {
                $disp .= "[$count]";
                if ($ev_type eq 'rental') {
                    $disp .= " " . ucfirst $ev->status;
                }
            }
            # only in program calendar
            # $disp .= $arr_lv;

            my $places = places($ev, 'all');
            my $sponsor = ($ev_type eq 'event' )? $ev->organization->name
                         :($ev_type eq 'rental')? 'MMC'
                         :                        ($ev->name =~ m{MMI}? 'MMI'
                                                 :                      'MMC');
            my $date_span = $ev_sdate->format("%b %e");
            if ($ev_sdate->month == $ev_edate->month) {
                if ($ev_sdate->day != $ev_edate->day) {
                    $date_span .= "-" . $ev_edate->day;
                }
            }
            else {
                $date_span .= " - " . $ev_edate->format("%b %e");
            }
            $disp .= "<br>$places<br>$sponsor<br>$date_span";
            $disp =~ s{'}{&apos;}g;
            $disp =~ s{"}{&quot;}g;

            # tidy up the date_span for the printable row
            $date_span =~ s{^([a-z]+)([\d\s-]+)$}{$2}i;

            # for the row in the details table
            my $printable_row
                = join '',
                  map { "<td>$_</td>" }

                  $date_span,

                  ($staff? "<a target=happening href='/$ev_type/view/"
                           . $ev->id
                           . "'>"
                           . $event_name
                           . "</a>"

                   :       $event_name) . ($ev->cancelled? $cancelled: ''),

                  places($ev, 'all')
                  ;

            if ($ev_type eq 'rental') {
                $printable_row .= "<td>&nbsp;</td>"     # prog reg count
                               .  "<td align=center>$count</td>"
                               ;
                               # more below
            }
            elsif ($ev_type eq 'program') {
                my $clusters =
                    join ', ',
                     map {
                         $_->name()
                     }
                     reserved_clusters($c, $ev_id, 'program')
                     ;
                $printable_row .= "<td align=right>$count&nbsp;&nbsp;</td>"
                               .  "<td></td><td></td>"
                                         # no rental count/status
                               .  "<td align=center>$arr_lv_longer</td>"
                               .  "<td align=left>$clusters</td>"
                               ;
            }

            my $border = $black;
            if ($ev_type eq 'rental') {
                my $clusters =
                    join ', ',
                    map {
                        $_->name()
                    }
                    reserved_clusters($c, $ev_id, 'rental')
                    ;
                if (!$ev->status) {
                    # how did the Rental status get unset???
                    $ev->update({
                        status => 'tentative',
                    });
                }
                $border = $im->colorAllocate(
                    $string{"rental_" . $ev->status . "_color"} =~ m{\d+}g,
                );
                $printable_row .= $ev->status_td()
                               .  "<td align=center>$arr_lv_longer</td>"
                               .  "<td align=left>$clusters</td>"
                               ;
            }
            elsif ($ev_type eq 'event') {
                $border = $im->colorAllocate(
                        $string{cal_event_color} =~ m{\d+}g);
            }

            # we're finally ready to draw the rectangle
            #
            $im->setThickness($event_border);
            $im->rectangle($x1, $y1, $x2, $y2, $border);
            $im->setThickness(1);

            $im->filledRectangle($x1+1, $y1+1, $x2-1, $y2-1, $color);

            if ($full_begins) {
                # does this date appear in this cal?
                if ($dr->sdate <= $full_begins
                    &&
                    $full_begins <= $dr->edate
                ) {
                    $im->setStyle($white, $white, $white, $white,
                                  $black, $black, $black, $black,
                                 );
                    my $x3 = $normal_end_day * $day_width - $day_width/2;
                    $im->setThickness(2);
                    $im->line($x3, $y1+1, $x3, $y2-1, gdStyled);
                    $im->setThickness(1);
                }
            }

            # print the event name in the rectangle,
            # as much as will fit and then it will overflow.
            #
            $im->string(gdGiantFont, $x1 + 3, $y1 + 2,
                        $event_name, $black);
                            # removed $arr_lv above - only in program calendar

            # add to the image map
            #
            $imgmaps{$key} .= "<area shape='rect' coords='$x1,$y1,$x2,$y2'\n";
            if ($staff) {
                $imgmaps{$key} .= "    target=happening\n"
                               .  "    href='" . $ev->link . "'\n"
            }
            $imgmaps{$key} .=
  qq!    onmouseover="return overlib('$disp',!
. qq! MOUSEOFF, FGCOLOR, '#FFFFFF', BGCOLOR, '#333333',!
. qq! BORDER, 2, TEXTFONT, 'Verdana', TEXTSIZE, 5, WRAP)"\n!
. qq!    onmouseout="return nd();">\n!;
            $details{$key} .= "<tr>$printable_row</tr>\n";
        }       # keys of the calendar month images/maps the event spans
    }       # events

    #
    # generate the jump image and map
    #
    my $jump_name = "im" 
                  . 'J'
                  . sprintf("%04d%02d%02d%02d%02d%02d", 
                            (localtime())[reverse (0 .. 5)])
                  . ".png"
                  ;
    my $jump_map = "<map name=jump>\n";
    my $nyears = $end_year - $start_year + 1;

    # 10 pixels per month, 15 between years
    my $jim = GD::Image->new($nyears * 135, 21);
    my $black = $jim->colorAllocate(0, 0, 0);
    my $white = $jim->colorAllocate(255, 255, 255);
    $jim->fill(2, 2, $white);
    for my $yr (1 .. $nyears) {
        my $x = ($yr-1)*135;
        $jim->line($x, 20, $x + 120, 20, $black);
        for my $m (0 .. 12) {
            my $x1 = $x + $m*10;
            $jim->line($x1, 20, $x1, 18, $black);
            next if $m == 12;
            my $ym = sprintf("%4d%02d", $start_year+$yr-1, $m+1);
            if ($ym > $max_ym) {
                $ym = $max_ym;
            }
            if ($ym < $min_ym) {
                $ym = $min_ym;
            }
            $jump_map .= "<area shape='rect' coords='"
                      . join(',', $x1, 0, $x1+10, 20)
                      .  "' href='#$ym'"
. qq! onmouseover="return overlib('!
. $month_name[$m]
#. " " . sprintf("%02d", ($start_year+$yr-1) % 100)
. qq!', MOUSEOFF, FGCOLOR, '#FFFFFF', BGCOLOR, '#333333', BORDER, 2,!
. qq! TEXTFONT, 'Verdana', TEXTSIZE, 5, WIDTH, 50)"!
# 50 => 95 if with year
. qq! onmouseout="return nd();">\n!;
        }
        $jim->string(gdGiantFont, $x + 45, 1,
                     $start_year+$yr-1, $black);
    }
    open my $jpng, ">", "root/static/images/$jump_name"
        or die "no $jump_name: $!\n";
    print {$jpng} $jim->png;
    close $jpng;
    $jump_map .= "</map>";
    #
    # generate the HTML output
    #
    my $det_keys = join ',',
                    map { "'$_'" }
                   grep { $details{$_} }
                   keys %details;
    my $content = <<"EOH";
<html>
<head>
<script type="text/javascript">
var newwin;
function popup(url, height) {
    newwin = window.open(
        url, 'reg_search_help',
        'height=' + height + ',width=550, scrollbars'
    );
    if (window.focus) {
        newwin.focus();
    }
    newwin.moveTo(700, 0);
}
</script>
<title>Calendar</title>
<link rel="stylesheet" type="text/css" href="/static/cal.css" />
<script type="text/javascript" src="/static/js/overlib.js"><!-- overLIB (c) Erik Bosrup --></script>
<script>
var img_state = 'block';
// state of the checkbox named 'detail'
var det_state = 'none';
var months = new Array($det_keys);
function detail_toggle(key) {
    if (key == 0) {
        det_state = (det_state == 'block')? 'none': 'block';
        for (var i = 0; i < months.length; ++i) {
            var el = document.getElementById('det' + months[i]);
            // may not be there - if Personal Retreat??
            if (el != null) {
                el.style.display = det_state;
            }
            var checkbox = document.getElementById('detail' + months[i]);
            if (checkbox) {
                checkbox.checked = det_state == 'block';
            }
        }
    }
    else {
        var checkbox = document.getElementById('detail' + key);
        var el = document.getElementById('det' + key);
        el.style.display = checkbox.checked? 'block': 'none';
    }
}
function image_toggle() {
    img_state = (img_state == 'block')? 'none': 'block';
    for (var i = 0; i < months.length; ++i) {
        var el = document.getElementById('img' + months[i]);
        // may not be there - if Personal Retreat
        if (el != null)
            el.style.display = img_state;
        // don't break the page if no images
        el = document.getElementById('break' + months[i]);
        // may not be there - if Personal Retreat
        if (el != null)
            el.style.display = img_state;
    }
}
</script>
</head>
<body>
$jump_map
<p>
EOH
    my $jump_img = $c->uri_for("/static/images/$jump_name");
    my @pr_color  = $string{cal_pr_color}  =~ m{\d+}g;
    my $arr_color = d3_to_hex($string{cal_arr_color});
    my $lv_color  = d3_to_hex($string{cal_lv_color});
    # ??? optimize - skip a $cals entirely if no PRs - have a flag
    # in the object.
    CAL:
    for my $key (sort keys %cals) {
        if ($ym_param && $key > $ym_param) {
            #
            # this month is an extra one - don't show it.
            # this happens when we request just one month
            # but an event in this month overlaps to the next one.
            # we may have had to generate the extra month (to avoid an even
            # uglier kludge) but we don't need to show it.
            #
            next CAL;
        }
        my $ac = $cals{$key};
        my $m = substr($key, 4, 2);
        $m =~ s{^0}{};      # worry about octal constant???
        my $im = $ac->image;

        # write the calendar images to be used shortly
        my $cal_name = "im" 
                       . $key 
                       . sprintf("%04d%02d%02d%02d%02d%02d", 
                                 (localtime())[reverse (0 .. 5)])
                       . ".png"
                       ;
        open my $imf, ">", "root/static/images/$cal_name"
            or die "no $cal_name: $!\n"; 
        print {$imf} $im->png;
        close $imf;

        my $month_name = $ac->sdate->format("%B %Y");
        # ??? rework using HEREDOC?
        $content .= "<a name=$key></a>\n<span class=hdr>"
                  . $month_name
                  . "</span>"
                  . "<img border=0 class=jmptable src=$jump_img usemap=#jump>"
                  . "<span class=datefld>Details <input type=checkbox id=detail$key onclick='detail_toggle($key)'></span>";

        $content .= "<p>\n";
        my $image = $c->uri_for("/static/images/$cal_name");
        $content .= <<"EOH";
<div id=img$key>
<img border=0 src='$image' usemap='#$key'>
</div>
<map name=$key>
$imgmaps{$key}</map>
<p>
EOH
        if ($details{$key}) {
            $content .= <<"EOH";
<div id=det$key style="display: none">
<p>
<ul>
<table cellpadding=3>
<tr>
<th align=left   valign=bottom>Date</th>
<th align=left   valign=bottom>Name</th>
<th align=left   valign=bottom>Place</th>
<th align=center valign=bottom>Reg<br>Count</th>
<th align=center  valign=bottom colspan=2>Rental<br>Max/Reserved&nbsp;&nbsp;Status</th>
<th align=center valign=bottom>Arrive/Leave</th>
<th align=left valign=bottom>Reserved Clusters</th>
</tr>
$details{$key}
</table>
</ul>
</div>
<div id=break$key style='page-break-after:always'></div>
EOH
        }
    }
    $content .= <<"EOH";
</body>
</html>
EOH
    if (! $public) {
        $content .= <<"EOH";
<script type="text/javascript">
document.form.end.focus();
</script>
EOH
    }
    if ($public) {
        # clear the user's state
        $c->logout;

        # fix up the content and then
        # ftp it all to www.mountmadonna.org
        #
        $content =~ s{http://.*?/images/}{}g;
        $content =~ s{/static/}{};
        $content =~ s{/static/js/}{};
        open my $cal, ">", "root/static/pubcal_index.html"
            or die "cannot open index.html: $!";
        my $updated = get_time()->ampm() . " " . today()->format("%b %e");
        print {$cal} <<"EOH";
<span class=cal_head>
Future Events at Mount Madonna Center
<span class=updated>Updated $updated</span>
<span class=cal_help><a href="javascript:popup('pubcal_help.html', 620);">Help</a></span>
</span>
EOH
        print {$cal} $content;
        close $cal;
        my ($jmp_image)  = $content =~ m{src=(imJ\d+[.]png)};
        my @cal_images = $content =~ m{src='(im\d+[.]png)'}g;
        my $ftp = Net::FTP->new($string{ftp_site},
                                Passive => $string{ftp_passive})
            or die "cannot connect to ...";    # not die???
        $ftp->login($string{ftp_login}, $string{ftp_password})
            or die "cannot login ", $ftp->message; # not die???
        # thanks to jnap and haarg
        # a nice HACK to force Extended Passive Mode:
        local *Net::FTP::pasv = \&Net::FTP::epsv;
        $ftp->cwd($string{ftp_dir})
            or die "cannot cwd ", $ftp->message; # not die???
        $ftp->cwd("calendar")
            or die "cannot cwd ", $ftp->message; # not die???
        for my $f ($ftp->ls()) {
            $ftp->delete($f);
        }
        $ftp->ascii();
        $ftp->put("root/static/pubcal_index.html", "index.html");
        $ftp->put("root/static/js/overlib.js",     "overlib.js");
        $ftp->put("root/static/cal.css",           "cal.css");
        $ftp->put("root/static/help/pubcal_help.html", "pubcal_help.html");
        $ftp->binary();
        for my $im (@cal_images, $jmp_image) {
            $ftp->put("root/static/images/$im", $im);
        }
        $ftp->quit();
        # tidy up
        #
        $c->res->output("sent");
    }
    else {
        $c->res->output($go_form . $content);
    }
}

1;
