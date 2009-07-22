use strict;
use warnings;
package RetreatCenter::Controller::Event;
use base 'Catalyst::Controller';

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
    meetingplace_table
    places
    tt_today
    stash
    reserved_clusters
/;
use GD;
use ActiveCal;
use DateRange;      # imports overlap
use Global qw/
    %string
/;

use lib '../../';       # so you can do a perl -c here.

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{sponsor_opts} = <<"EOH";
<option value="Center">Center
<option value="School">School
<option value="Institute">Institute
<option value="Other">Other
EOH
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "event/create_edit.tt2";
}

my %P;
my @mess;
sub _get_data {
    my ($c) = @_;

    %P = %{ $c->request->params() };
    @mess = ();
    if (empty($P{name})) {
        push @mess, "Name cannot be blank";
    }
    # dates are either blank or converted to d8 format
    for my $d (qw/ sdate edate /) {
        my $fld = $P{$d};
        if (! $fld =~ /\S/) {
            push @mess, "missing date field";
            next;
        }
        if ($d eq 'edate') {
            Date::Simple->relative_date(date($P{sdate}));
        }
        my $dt = date($fld);
        if ($d eq 'edate') {
            Date::Simple->relative_date();
        }
        if ($fld && ! $dt) {
            # tell them which date field is wrong???
            push @mess, "Invalid date: $fld";
            next;
        }
        $P{$d} = $dt? $dt->as_d8()
                   :     "";
    }
    if (!@mess && $P{sdate} > $P{edate}) {
        push @mess, "End date must be after the Start date";
    }
    if (! empty($P{max}) && $P{max} !~ m{^\s*\d+\s*$}) {
        push @mess, "Max must be an integer";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "event/error.tt2";
    }
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;

    #
    # check for a duplicate event
    #
    my @events = model($c, 'Event')->search({
        name => $P{name},
        sdate => $P{sdate},
        edate => $P{edate},
    });
    if (@events) {
        stash($c,
            mess     => "Duplicate event: <a href=/event/view/"
                      . $events[0]->id()
                      . ">$P{name}</a>",
            template => "event/error.tt2",
        );
        return;
    }

    my $p = model($c, 'Event')->create(\%P);
    my $id = $p->id();
    $c->response->redirect($c->uri_for("/event/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $ev = model($c, 'Event')->find($id);
    my $sdate = $ev->sdate();
    my $nmonths = date($ev->edate())->month()
                - date($sdate)->month()
                + 1;
    stash($c,
        event          => $ev,
        daily_pic_date => $ev->sdate(),
        cal_param      => "$sdate/$nmonths",
        template       => "event/view.tt2",
    );
}

sub list : Local {
    my ($self, $c) = @_;

    my $today = tt_today($c)->as_d8();
    stash($c,
        pg_title  => "Events",
        events    => [
            model($c, 'Event')->search(
                { sdate => { '>=', $today } },
                { order_by => 'sdate' },
            )
        ],
        event_pat => "",
        template  => "event/list.tt2",
    );
}

sub listpat : Local {
    my ($self, $c) = @_;

    my $event_pat = $c->request->params->{event_pat};
    if (empty($event_pat)) {
        $c->forward('list');
        return;
    }
    my $cond;
    if ($event_pat =~ m{(^[fs])(\d\d)}i) {
        my $seas = $1;
        my $year = $2;
        $seas = lc $seas;
        if ($year > 70) {
            $year += 1900;
        }
        else {
            $year += 2000;
        }
        my ($d1, $d2);
        if ($seas eq 'f') {
            $d1 = $year . '1001';
            $d2 = ($year+1) . '0331';
        }
        else {
            $d1 = $year . '0401';
            $d2 = $year . '0930';
        }
        $cond = {
            sdate => { 'between' => [ $d1, $d2 ] },
        };
    }
    elsif ($event_pat =~ m{((\d\d)?\d\d)}) {
        my $year = $1;
        if ($year > 70 && $year <= 99) {
            $year += 1900;
        }
        elsif ($year < 70) {
            $year += 2000;
        }
        $cond = {
            sdate => { 'between' => [ "${year}0101", "${year}1231" ] },
        };
    }
    else {
        my $pat = $event_pat;
        $pat =~ s{\*}{%}g;
        $cond = {
            -or => [
                name  => { 'like' => "${pat}%" },
                descr => { 'like' => "${pat}%" },
            ],
        };
    }
    stash($c,
        pg_title  => "Events",
        events    => [
            model($c, 'Event')->search(
                $cond,
                { order_by => 'sdate desc' },
            )
        ],
        event_pat => $event_pat,
        template  => "event/list.tt2",
    );
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Event')->find($id);
    $c->stash->{event} = $p;
    my $sponsor_opts = "";
    for my $s (qw/Center School Institute Other/) {
        $sponsor_opts .= "<option value='$s'"
                       . (($s eq $p->sponsor)? " selected": "")
                       . ">$s\n";
    }
    $c->stash->{sponsor_opts} = $sponsor_opts;
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "event/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    my $e = model($c, 'Event')->find($id);
    my $names = "";
    if (   $e->sdate ne $P{sdate}
        || $e->edate ne $P{edate}
        || $e->max   <  $P{max}
    ) {
        # invalidate the bookings as the dates/max have changed
        my @bookings = model($c, 'Booking')->search({
            event_id => $id,
        });
        $names = join '<br>', map { $_->meeting_place->name } @bookings;
        for my $b (@bookings) {
            $b->delete();
        }
    }
    $e->update(\%P);
    if ($names) {
        $c->stash->{event} = $e;
        $c->stash->{names} = $names;
        $c->stash->{template} = "event/mp_warn.tt2";
    }
    else {
        $c->response->redirect($c->uri_for("/event/view/" . $e->id));
    }
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    model($c, 'Event')->search(
        { id => $id }
    )->delete();
    $c->response->redirect($c->uri_for('/event/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

#
# 40, 20 are the heights of the event rectangles.
# put in ActiveCal??
#
sub calendar : Local {
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

    Global->init($c);

    my $std_prog_arr = get_time($string{reg_start});
    my $std_prog_lv  = get_time($string{prog_end});
    my $std_rental_arr = get_time($string{rental_start_hour});
    my $std_rental_lv  = get_time($string{rental_end_hour});

    my $start_param = trim($c->request->params->{start});
    if (!$start_param) {
        $start_param = $the_start;
    }
    my $start;
    if ($start_param) {
        if (my ($m, $y) = $start_param =~ m{^(\d+)\D+(\d+)$}g) {
            # month year
            $y += 2000 if $y < 1900;
            $start = date($y, $m, 1);
        }
        else {
            my $dt = date($start_param);
            if ($dt) {
                $start = $dt;
            }
            else {
                $start = tt_today($c);
            }
        }
    }
    else {
        $start = tt_today($c);
    }
    $start_param = $start->format("%D");
    my $start_year = $start->year;
    my $start_month = $start->month;
    my $min_ym = sprintf("%4d%02d", $start_year, $start_month);
    my $the_first = sprintf("%4d%02d%02d", $start_year, $start_month, 1);

    # optional end date - otherwise it goes to the last happening date
    # unless, that is, we have a the_end method parameter
    my $end_param = trim($c->request->params->{end});
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
<form action='/event/calendar' name=form>
<span class=datefld>Images <input type=checkbox name=images checked onclick='image_toggle()'></span>
<span class=datefld>All Details <input type=checkbox name=detail onclick='detail_toggle(0)'></span>
<span class=datefld>Start</span> <input type=text name=start size=10 value='$start_param'>
<span class=datefld>End</span> <input type=text name=end size=10 value='$end_param'>
<span class=datefld><input class=go type=submit value="Go"></span>
&nbsp;&nbsp;
<a href="javascript:popup('/static/help/calendar.html', 620);">How?</a>
&nbsp;&nbsp;
<a href="javascript:popup('/event/cal_colors', 670);">Colors?</a>
</form>
</div>
<p>
EOH

    # put this in Global???
    my ($no_where) = model($c, 'MeetingPlace')->search({
        name => 'No Where',
    });
    my $no_where_ord = ($no_where)? $no_where->disp_ord(): 0;

    my @events;
    for my $ev_kind (qw/Event Program Rental/) {
        my @prog_opt = ();
        if ($ev_kind eq "Program") {
            @prog_opt = (
                level => { 'not in',  [qw/ D C M /] },
            );
        }
        push @events, model($c, $ev_kind)->search({
                          edate => { '>=', $the_first },
                          @opt_end,
                          name  => { -not_like, "%personal%retreats%" },
                          @prog_opt,
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

    # get all relevant bookings
    my @bookings = model($c, 'Booking')->search({
                       edate => { '>=', $the_first },
                   });

    # get all meeting places in a hash indexed by id
    # cache this?
    my %meeting_places = map { $_->id => $_ }
                         model($c, 'MeetingPlace')->all();

    my %cals;       # a hash of ActiveCal objects indexed by yearmonth
    my %imgmaps;    # the image maps for each calendar image
    my %details;    # for the printable version
    #
    # initialize the cals and imgmaps
    #
    my $year = $start_year;
    my $month = $start_month;
    while ($year < $end_year || ($year == $end_year && $month <= $end_month)) {
        my $key = sprintf("%04d%02d", $year, $month);
        $cals{$key} = ActiveCal->new($year, $month, \@events, $no_where_ord);
        $imgmaps{$key} = "";
        $details{$key} = "";
        ++$month;
        if ($month > 12) {
            $month = 1;
            ++$year;
        }

    }
    #
    # sort the events by start date so that
    # a later event will overwrite one to its left
    #
    EVENT:
    for my $ev (sort { $a->sdate <=> $b->sdate } @events) {
        my $ev_type = ref($ev);
        $ev_type =~ s{.*::}{};
        $ev_type = lc $ev_type;
        my $ev_type_id = "$ev_type\_id";

        # draw on the right image(s)
        #
        my $ev_sdate = $ev->sdate_obj;
        my $ev_edate = $ev->edate_obj;

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
        $event_name =~ s{ \d\d/\d\d$}{}; # tidy up ending mm/yy
                                         # not really needed
        $event_name =~ s{^MMI-}{};       # the front of MMI programs
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
                $count = $max . "/$count";
            }
            else {
                $count = $max;
            }
        }
        my $ev_id = $ev->id;
        my $title = $ev->title;

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

            # this does a get of the meeting place record???
            # yes, - replace it!!!
            my @places = sort { $a->disp_ord <=> $b->disp_ord }
                         map  { $_->meeting_place }
                         grep { $_->$ev_type_id == $ev_id }
                         @bookings;
            #
            # if no meeting place assigned hopefully put it SOMEwhere.
            # to alert the user that it is dangling homeless.
            #
            if (! @places) {
                if ($ev_type eq 'program' && $ev->rental_id()) {
                    # this is a program with a parallel Rental
                    next EVENT;     # skip it entirely
                }
                if ($no_where) {
                    push @places, $no_where;
                }
            }
            my $im = $cal->image;
            my $black = $cal->black;
            my $white = $cal->white;

            # ???do not keep recomputing various things inside this loop
            # ??? get all meeting places once into a hash where key = meet_id
            #
            # ??? multiple meeting places - in detail table???
            # ??? use abbrevs not full name???
            my $details_shown = 0;
            for my $pl (@places) {
                my ($r, $g, $b) = $pl->color =~ m{(\d+)}g;
                my $color = $im->colorAllocate($r, $g, $b);
                    # ??? do the above once for all meeting places
                    # then index into a hash for the color.

                my $x1 = ($dr->sdate->day-1) * $day_width;
                my $x2 = $dr->edate->day * $day_width;

                # shall we indent the left and right side?
                # one day events are a special case.
                if ($ev_sdate != $ev_edate) {
                    # not overlapping from prior month?
                    if ($dr->sdate == $ev_sdate) {
                        $x1 += $day_width/2;
                    }
                    # not overflowing to the next month?
                    if ($dr->edate == $ev_edate) {
                        $x2 -= $day_width/2;
                    }
                }

                my $y1 = $pl->disp_ord * 40 + 2;
                        # +2 for the thick border not impeding the top line
                my $y2 = $y1 + 20;
                my $place_name = $pl->abbr;
                if ($place_name eq '-') {
                    $place_name = "";
                }
                else {
                    $place_name = " ($place_name)";
                }

                # to display in the overlib popup:
                #
                my $disp = $event_name . $place_name;
                if (length $count) {
                    $disp .= "[$count]";
                    if ($ev_type eq 'rental') {
                        $disp .= " " . ucfirst $ev->status;
                    }
                }
                $disp .= $arr_lv;

                # which is longest?
                my $ld = length($disp);
                my $lt = length($title);
                my $width = ($ld > $lt)? $ld: $lt;
                $disp .= "<br>$title<br>";
                my $date_span = $ev_sdate->format("%b %e");
                if ($ev_sdate->month == $ev_edate->month) {
                    if ($ev_sdate->day != $ev_edate->day) {
                        $date_span .= "-" . $ev_edate->day;
                    }
                }
                else {
                    $date_span .= " - " . $ev_edate->format("%b %e");
                }
                $disp .= $date_span;
                # tidy up the date_span for the printable row
                $date_span =~ s{^([a-z]+)([\d\s-]+)$}{$2}i;

                my $printable_row
                    = join '',
                      map { "<td>$_</td>" }

                      $date_span,

                      ($staff? "<a target=happening href='/$ev_type/view/"
                               . $ev->id
                               . "'>"
                               . $event_name
                               . "</a>"

                       :       $event_name),

                      places($ev)
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
                $disp =~ s{'}{\\'}g;    # what if name eq Mother's Day?

                my $border = $black;
                if ($ev_type eq 'rental') {
                    my $clusters =
                        join ', ',
                        map {
                            $_->name()
                        }
                        reserved_clusters($c, $ev_id, 'rental')
                        ;
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
                                      $color, $color, $color, $color,
                                     );
                        my $x3 = $normal_end_day * $day_width - $day_width/2;
                        $im->setThickness(2);
                        $im->line($x3, $y1+1, $x3, $y2-1, gdStyled);
                        $im->setThickness(1);
                    }
                }

                # print the event name in the rectangle,
                # as much as will fit and then it will overflow.
                $im->string(gdGiantFont, $x1 + 3, $y1 + 2,
                            $event_name . $arr_lv, $black);

                # add to the image map
                $imgmaps{$key} .= "<area shape='rect' coords='$x1,$y1,$x2,$y2'\n";
                if ($staff) {
                    $imgmaps{$key} .= "    target=happening\n"
                                   .  "    href='" . $ev->link . "'\n"
                }
                $imgmaps{$key} .=
      qq!    onmouseover="return overlib('$disp',!
    . qq! MOUSEOFF, FGCOLOR, '#FFFFFF', BGCOLOR, '#333333',!
    . qq! BORDER, 2, TEXTFONT, 'Verdana', TEXTSIZE, 5, WIDTH, $width * 20)"\n!
    . qq!    onmouseout="return nd();">\n!;
                if (! $details_shown) {
                    $details{$key} .= "<tr>$printable_row</tr>\n";
                    $details_shown = 1;
                }
            }       # places the event meets in 
        }       # keys of the calendar month images/maps the event spans
    }       # events
    #
    # look for abutting events in the same meeting place.
    # i.e. two bookings for a meeting place - one that ends
    # and one that starts on the same date.
    # a single day event does not count as such.
    #
    # Mark such with a solid line.
    #
    my %edges;
    # ??? is there a class method to get colors?
    # or is it a per image thing?
    BOOKING:
    for my $b (@bookings) {
        DATE:
        for my $dt ($b->sdate, $b->edate) {
            my $key = $b->meet_id . '-' . $dt;
            if (exists $edges{$key} && $b != $edges{$key}) {

                # we now know where to draw
                my ($meet_id, $ym, $day) = $key =~ m{(\d+)-(\d{6})(\d\d)};
                if (! exists $cals{$ym}) {
                    # this IS an abuttment but it is 
                    # not visible in our limited range of months
                    # ideally we should limit our looking to just
                    # the bookings in the month range we are concerned about.
                    # but that's tricky, too.
                    next DATE;
                }
                my $cal = $cals{$ym};
                my $im = $cal->image;

                # these tweakings of pixels were determined by trial and error
                #
                my $y1 = ($meeting_places{$meet_id}->disp_ord()) * 40 + 3;
                my $y2 = $y1 + 20 - 2;
                my $x = ($day-1) * $day_width + $day_width/2 - 1;
                $im->setThickness($string{cal_abutt_thickness});

                # two ways to mark it
                #
                if (! empty($string{cal_abutt_style})) {
                    # 'barber pole'
                    my $red   = $cal->red();
                    my $white = $cal->white();
                    my $black = $cal->black();
                    my $abutt = $cal->abutt();
                    $im->setStyle(
                        map {
                            $_ eq 'r'? $red
                           :$_ eq 'w'? $white
                           :$_ eq 'a'? $abutt
                           :           $black
                        }
                        split m{}, $string{cal_abutt_style}
                    );
                    $im->line($x, $y1, $x, $y2, gdStyled);
                }
                else {
                    # solid color
                    $im->line($x, $y1, $x, $y2, $cal->abutt());
                }



                $im->setThickness(1);
                next BOOKING;
            }
            $edges{$key} = $b;
        }
    }
    #
    # personal retreats
    #
    # a PR might begin in a prior season
    # and continue through the next into the current month range.
    # get the current, the previous and subsequent PR seasons.
    # the 30*6 is not exactly 6 months prior but will suffice.
    #
    my $the_prev = date($the_first) - 30*6;
    $the_prev = $the_prev->as_d8();
    my @pr_ids = map { $_->id }     # ???wasteful!  - just to get the ids
                                    # we get the entire object.
                 model($c, 'Program')->search(
                    {
                        edate => { '>=', $the_prev },
                        name  => { 'like' => "Personal Retreats%" },
                    },
                 );
    my @pr_regs = ();
    if (@pr_ids) {
        @pr_regs = model($c, 'Registration')->search(
                       {
                           program_id => { 'in', \@pr_ids },
                           date_end   => { '>=', $the_first },
                           cancelled  => '',
                       },
                       { order_by => 'date_start' }
                   );
    }
    for my $pr (@pr_regs) {
        my $sdate = $pr->date_start_obj;
        my $edate = $pr->date_end_obj;
        KEY:
        for my $key (ActiveCal->keys($sdate, $edate)) {
            my $cal = $cals{$key};
            if (! $cal) {
                next KEY;
                # this event apparently begins in a prior month
                # and overlaps into the first shown month???
                # like today is April 10th and the event is from
                # March 29th to April 4th.
                # we cover this in the current month so can skip this???.
            }
            my $dr = overlap(DateRange->new($sdate, $edate), $cal);
            $cal->add_pr($dr->sdate->day, $dr->edate->day, $pr);
        }
    }

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
    my $fmt = "#%02x%02x%02x";
    my $arr_color = sprintf $fmt, $string{cal_arr_color} =~ m{\d+}g;
    my $lv_color  = sprintf $fmt, $string{cal_lv_color}  =~ m{\d+}g;
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
        my $pr_color = $im->colorAllocate(@pr_color);
        my $black = $ac->black;

        # PRs
        for my $d (1 .. $ac->ndays) {
            my $arr_ref = $ac->get_prs($d);
            if (defined $arr_ref) {
                my $day = date($key . sprintf("%02d", $d));
                my $day_name = $day->format("%a");
                my @prs = sort @$arr_ref;
                my $n = @prs;
                my $pr_links = "";
                for my $pr (@prs) {
                    my ($name, $id, $status) = split /\t/, $pr;
                    $name =~ s{'}{\\'}g;    # for O'Dwyer etc.
                    my $bg = ($status eq 'lv' )? $lv_color
                            :($status eq 'arr')? $arr_color
                            :                    '#FFFFFF';
                    $pr_links .= "<tr>";
                    if ($staff) {
                        $pr_links
                           .= "<td><a class=pr_links target=happening href="
                           . $c->uri_for("/registration/view/$id")
                           . ">$name</a></td><td bgcolor=$bg>$status"
                           ;
                    }
                    else {
                        # no access - just view
                        $pr_links .= "<td>$name</td>"
                                  .  "<td bgcolor=$bg>$status</td>";
                    }
                    $pr_links .= "</tr>";
                }
                my $x1 = $day_width*($d-1);
                my $y1 = $ac->cal_height - 20 - 1;
                my $x2 = $x1 + $day_width;
                my $y2 = $y1 + 20;
                $im->line($x1, $y1, $x2, $y1, $black);
                    # just draw the upper line, yeah.
                $im->filledRectangle($x1+1, $y1+1, $x2-1, $y2-1,
                                     $pr_color);
                my $offset = ($n < 10)? 11: 7;
                $im->string(gdGiantFont, $x1+$offset, $y1+3, $n, $black);
                # ??? rework this to use HEREDOC <<
                $imgmaps{$key} .= "<area shape='rect' "
                               .  "coords='$x1,$y1,$x2,$y2'\n"
. qq! onclick="return overlib('<center>$day_name!
. qq! $month_name[$m-1] $d</center><p><table cellpadding=2>!
. qq!$pr_links</table>',!
             # very cool to use $m-1 inside index inside ' inside " !!!
. qq! STICKY, MOUSEOFF, TEXTFONT, 'Verdana', TEXTSIZE, 5, WRAP,!
. qq! CELLPAD, 7, FGCOLOR, '#FFFFFF', BORDER, 2, VAUTO)"!
. qq! onmouseout="return nd();">\n!
                    if ! $public;       # zowee! fun!
            }
        }

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

#
# what about a max for the event?
#
sub meetingplace_update : Local {
    my ($self, $c, $id) = @_;

    my $e = $c->stash->{event} = model($c, 'Event')->find($id);
    $c->stash->{meetingplace_table}
        = meetingplace_table($c, $e->max, $e->sdate, $e->edate, $e->bookings());
    $c->stash->{template} = "event/meetingplace_update.tt2";
}

sub meetingplace_update_do : Local {
    my ($self, $c, $id) = @_;

    my $e = model($c, 'Event')->find($id);
    my @cur_mps;
    my %seen = ();
    for my $k (sort keys %{$c->request->params}) {
        #
        # keys are like this:
        #     mp45
        # or
        #     mpbr23
        # all mp come before any mpbr
        #
        my ($d) = $k =~ m{(\d+)};
        my $br = ($k =~ m{br})? 'yes': '';
        push @cur_mps, [ $d, $br ] unless $seen{$d}++;
    }
    # delete all old bookings and create the new ones.
    model($c, 'Booking')->search(
        { event_id => $id },
    )->delete();
    for my $mp (@cur_mps) {
        model($c, 'Booking')->create({
            meet_id    => $mp->[0],
            program_id => 0,
            rental_id  => 0,
            event_id   => $id,
            sdate      => $e->sdate(),
            edate      => $e->edate(),
            breakout   => $mp->[1],
        });
    }
    # show the event again - with the updated meeting places
    view($self, $c, $id);
    $c->forward('view');
}

sub cal_colors : Local {
    my ($self, $c) = @_;

    my $html = <<"EOF";
<h3>Meeting Places - Names and Colors</h3>
<table cellpadding=5>
EOF
    my @mps = model($c, 'MeetingPlace')->search(
        {
        },
        {
            order_by => 'disp_ord asc',
        }
    );
    my $fmt = "#%02x%02x%02x";
    for my $mp (@mps) {
        my $col = sprintf($fmt, $mp->color() =~ m{(\d+)}g);
        $html .= "<tr>"
              .  "<td>" . $mp->abbr() . "</td>"
              .  "<td>" . $mp->name() . "</td>"
              .  "<td bgcolor=$col width=40>&nbsp;</td>"
              .  "</tr>\n"
    }
    $html .= <<"EOF";
</table>
<h3>Rental Status - Border Color</h3>
<table cellpadding=5>
EOF
    for my $st (qw/
        tentative
        sent
        received
        due
        done
    /) {
        my $col = sprintf($fmt, $string{"rental_${st}_color"} =~ m{(\d+)}g);
        $html .= "<tr><td>\u$st</td><td bgcolor=$col width=40></td></tr>\n";
    }
    $html .= <<"EOF";
</table>
<p>
<a href='#' onclick="javascript:window.close();">Close</a>
EOF
    $c->res->output($html);
}

1;
