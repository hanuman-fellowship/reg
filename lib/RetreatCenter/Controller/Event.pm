use strict;
use warnings;
package RetreatCenter::Controller::Event;
use base 'Catalyst::Controller';

use Date::Simple qw/date today/;
use Util qw/
    empty
    model
    meetingplace_table
    places
/;
use GD;
use ActiveCal;
use DateRange;      # imports overlap
use Lookup;

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

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    @mess = ();
    if (empty($hash{name})) {
        push @mess, "Name cannot be blank";
    }
    if (empty($hash{descr})) {
        push @mess, "Description cannot be blank";
    }
    # dates are either blank or converted to d8 format
    for my $d (qw/ sdate edate /) {
        my $fld = $hash{$d};
        if (! $fld =~ /\S/) {
            push @mess, "missing date field";
            next;
        }
        if ($d eq 'edate') {
            Date::Simple->relative_date(date($hash{sdate}));
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
        $hash{$d} = $dt? $dt->as_d8()
                   :     "";
    }
    if (!@mess && $hash{sdate} > $hash{edate}) {
        push @mess, "End date must be after the Start date";
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

    my $p = model($c, 'Event')->create(\%hash);
    my $id = $p->id();
    $c->response->redirect($c->uri_for("/event/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{event} = model($c, 'Event')->find($id);
    $c->stash->{template} = "event/view.tt2";
}

sub list : Local {
    my ($self, $c) = @_;

    my $today = today()->as_d8();
    $c->stash->{events} = [
        model($c, 'Event')->search(
            { sdate => { '>=', $today } },
            { order_by => 'sdate' },
        )
    ];
    $c->stash->{event_pat} = "";
    $c->stash->{template} = "event/list.tt2";
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
            name => { 'like' => "${pat}%" },
        };
    }
    $c->stash->{events} = [
        model($c, 'Event')->search(
            $cond,
            { order_by => 'sdate desc' },
        )
    ];
    $c->stash->{event_pat} = $event_pat;
    $c->stash->{template} = "event/list.tt2";
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
    if ($e->sdate ne $hash{sdate} || $e->edate ne $hash{edate}) {
        # invalidate the bookings as the dates have changed
        model($c, 'Booking')->search({
            event_id => $id,
        })->delete();
    }
    $e->update(\%hash);
    $c->response->redirect($c->uri_for("/event/view/" . $e->id));
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

sub calendar : Local {
    my ($self, $c) = @_;

    my @month_name = qw/
        Jan Feb Mar
        Apr May Jun
        Jul Aug Sep
        Oct Nov Dec
    /;

    Lookup->init($c);
    my $which = $c->request->params->{which};
    my $today = today();
    if ($which) {
        my $dt = date($which);
        if ($dt) {
            $today = $dt;
        }
    }
    my ($no_where) = model($c, 'MeetingPlace')->search({
        name => 'No Where',
    });
    my $start_year = $today->year;
    my $start_month = $today->month;
    my $min_ym = sprintf("%4d%02d", $start_year, $start_month);
    my $the_first = sprintf("%4d%02d%02d", $start_year, $start_month, 1);
    my @events;
    for my $ev_kind (qw/Event Program Rental/) {
        push @events, model($c, $ev_kind)->search({
                          edate => { '>=', $the_first },
                          name  => { -not_like, "Personal Retreats%" },
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

    # get all relevant bookings
    my @bookings = model($c, 'Booking')->search({
                       edate => { '>=', $the_first },
                   });

    # get all meeting places in a hash indexed by id
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
        $cals{$key} = ActiveCal->new($year, $month);
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
    my $day_width  = ActiveCal->day_width;
    my $cal_height = ActiveCal->cal_height;
    for my $ev (sort { $a->sdate <=> $b->sdate } @events) {
        my $ev_type = ref($ev);
        $ev_type =~ s{.*::}{};
        $ev_type = lc $ev_type;
        my $ev_type_id = "$ev_type\_id";

        # draw on the right image(s)
        #
        my $ev_sdate = $ev->sdate_obj;
        my $ev_edate = $ev->edate_obj;

        my ($full_begins, $ndays_in_normal, $normal_end_day, $extra_count);
        $extra_count = "";

        if ($ev_type eq 'program') {
            # is there a FULL program?
            # if so, use its end date instead.
            # AND draw a little dotted line on the day
            # when the FULL extension begins (or equivalently
            # when the normal length program ends).
            if ($ev->extradays) {
                my ($full_p) = model($c, 'Program')->find($ev->id + 1);
                $full_begins = $ev->edate_obj;
                $ndays_in_normal = $ev->edate_obj - $ev->sdate_obj;
                $normal_end_day = $ev->edate_obj->day;
                $ev_edate = $full_p->edate_obj;
                $extra_count = $full_p->reg_count;
            }
        }
        my $event_name = $ev->name;
        my $ev_count = $ev->count;
        my $count = $ev_count;
        if (length $count) {
            if (length $extra_count) {
                $count .= "+$extra_count";
            }
            elsif ($ev_type eq 'rental') {
                $count = $ev->max . ", $count";
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
                $cal = $cals{$today->format("%Y%m")};
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
            if (! @places && $no_where) {
                push @places, $no_where;
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
                my $disp = $event_name . $place_name;
                if (length $count) {
                    $disp .= "[$count]";
                    if ($ev_type eq 'rental') {
                        my $status = $ev->status;
                        $status =~ s{<td.*>(.*)</td>}{$1};
                        $disp .= " $status";
                    }
                }
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

                my $printable_row = join '',
                                    map { "<td>$_</td>" }
                                    $date_span,
                                    "<a target=happening href='/$ev_type/view/"
                                     . $ev->id
                                     . "'>"
                                     . $event_name
                                     . "</a>",
                                    places($ev);
                if ($ev_type eq 'rental') {
                    $printable_row .= "<td>&nbsp;</td>"
                                   .  "<td align=right>$count</td>";
                }
                elsif ($ev_type eq 'program') {
                    $printable_row .= "<td align=right>$count</td>";
                }
                $disp =~ s{'}{\\'}g;    # what if name eq Mother's Day?

                my $border = $black;
                if ($ev_type eq 'rental') {
                    if (! $ev->contract_sent) {
                        $border = $im->colorAllocate(
                            $lookup{rental_new_color} =~ m{\d+}g);
                    }
                    elsif (! ($ev->contract_received
                              && scalar($ev->payments) > 0
                             )
                    ) {
                        $border = $im->colorAllocate(
                            $lookup{rental_sent_color} =~ m{\d+}g);
                    }
                    elsif (! $ev->max_confirmed) {
                        $border = $im->colorAllocate(
                            $lookup{rental_deposit_color} =~ m{\d+}g);
                    }
                    else {
                        $border = $im->colorAllocate(
                            $lookup{rental_ready_color} =~ m{\d+}g);
                    }
                    $printable_row .= $ev->status;
                }
                elsif ($ev eq 'event') {
                    $border = $im->colorAllocate(
                            $lookup{event_color} =~ m{\d+}g);
                }

                $im->setThickness(4);
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
                # as much as will fit and then overflow it
                $im->string(gdLargeFont, $x1 + 3, $y1 + 2,
                            $event_name, $black);

                # add to the image map
                $imgmaps{$key} .= "<area shape='rect' coords='$x1,$y1,$x2,$y2'\n"
                               .  "    target=happening\n"
                               .  "    href='" . $ev->link . "'\n"
    . qq!    onmouseover="return overlib('$disp',!
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
    # Mark such with a dotted red line.
    #
    my %edges;
    # ??? is there a class method to get colors?
    # or is it a per image thing?
    BOOKING:
    for my $b (@bookings) {
        for my $dt ($b->sdate, $b->edate) {
            my $key = $b->meet_id . '-' . $dt;
            if (exists $edges{$key} && $b != $edges{$key}) {

                # we now know where to draw
                my ($meet_id, $ym, $day) = $key =~ m{(\d+)-(\d{6})(\d\d)};
                my $cal = $cals{$ym};
                my $im = $cal->image;
                my $red = $cal->red;
                my $white = $cal->white;

                my $y1 = ($meeting_places{$meet_id}->disp_ord()) * 40 + 3;
                my $y2 = $y1 + 20 - 2;
                # these tweakings of pixels were determined by trial and error

                my $x = ($day-1) * $day_width + $day_width/2 - 1;
                $im->setThickness(3);
                $im->setStyle($red, $red, $white, $white);
                $im->line($x, $y1, $x, $y2, gdStyled);
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
    my @pr_regs = model($c, 'Registration')->search(
                      {
                          program_id => { 'in', \@pr_ids },
                          date_end   => { '>=', $the_first },
                          cancelled  => '',
                      },
                      { order_by => 'date_start' }
                  );
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
            $jump_map .= "<area shape=rect coords='"
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
        $jim->string(gdLargeFont, $x + 45, 1,
                     $start_year+$yr-1, $black);
    }
    open my $jpng, ">", "root/static/images/jump.png"
        or die "no jump png: $!\n";
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
<head>
<link rel="stylesheet" type="text/css" href="/static/cal.css" />
<script type="text/javascript" src="/static/js/overlib.js"><!-- overLIB (c) Erik Bosrup --></script>
<script>
var state = 'block';
var months = new Array($det_keys);
function detail_toggle() {
    state = (state == 'block')? 'none': 'block';
    for (var i = 0; i < months.length; ++i) {
        //alert(months[i]);
        document.getElementById('det' + months[i]).style.display = state;
    }
}
</script>
</head>
<body>
$jump_map
<div class=whole>
<p>
EOH
    my $jump_img = $c->uri_for("/static/images/jump.png");
    my $firstcal = 1;
    my @pr_color = $lookup{pr_color} =~ m{\d+}g;
    # my $pr_bg = sprintf "#%02x%02x%02x", @pr_color;
    # ??? optimize - skip a $cals entirely if no PRs - have a flag
    # in the object.
    for my $key (sort keys %cals) {
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
                    my $bg = ($status eq 'lv' )? '#FF3333'
                            :($status eq 'arr')? '#33FF33'
                            :                    '#FFFFFF';
                    $pr_links .= "<tr><td><a class=pr_links target=happening href="
                               . $c->uri_for("/registration/view/$id")
                               . ">$name</a></td><td bgcolor=$bg>$status</td></tr>";
                }
                my $x1 = $day_width*($d-1);
                my $y1 = $cal_height - 20 - 1;
                my $x2 = $x1 + $day_width;
                my $y2 = $y1 + 20;
                #$im->rectangle($x1, $y1, $x2, $y2, $black);
                $im->line($x1, $y1, $x2, $y1, $black);
                    # could just draw the upper line, yeah.
                $im->filledRectangle($x1+1, $y1+1, $x2-1, $y2-1,
                                     $pr_color);
                my $offset = ($n < 10)? 11: 7;
                $im->string(gdLargeFont, $x1+$offset, $y1+3, $n, $black);
                $imgmaps{$key} .= "<area shape='rect' coords='$x1,$y1,$x2,$y2'\n"
. qq! onclick="return overlib('<center>$day_name $month_name[$m-1] $d</center><p><table cellpadding=2>$pr_links</table>',!
                    # very cool to use $m-1 inside index inside ' inside " !!!
. qq! STICKY, MOUSEOFF, TEXTFONT, 'Verdana', TEXTSIZE, 5, WRAP,!
. qq! CELLPAD, 7, FGCOLOR, '#FFFFFF', BORDER, 2)"!
. qq! onmouseout="return nd();">\n!;
            }
        }

        # write the calendar images to be used shortly
        open my $imf, ">", "root/static/images/$key.png"
            or die "not $key.png: $!\n"; 
        print {$imf} $im->png;
        close $imf;

        my $month_name = $ac->sdate->format("%B %Y");
        my $form = ($firstcal)? "<form action='/event/calendar'>": "";
        $content .= "$form<a name=$key>\n<span class=hdr>"
                  . $month_name
                  . "<img border=0 class=jmptable src=$jump_img usemap=#jump>";
        if ($firstcal) {
            my $go_form = <<"EOH";
<span class=datefld>Date</span> <input type=text name=which size=10>
<input class=go type=submit value="Go">
</form>
EOH
            $content .= "</span>\n";
            $content .= "<div class=details>Details <input type=checkbox name=detail checked onclick='detail_toggle()'></div>$go_form";
            $firstcal = 0;
        }
        $content .= "<p>\n";
        my $image = $c->uri_for("/static/images/$key.png");
        $content .= <<"EOH";
<img border=0 src='$image' usemap='#$key'>
<map name=$key>
$imgmaps{$key}</map>
<p>
EOH
        if ($details{$key}) {
            $content .= <<"EOH";
<div id=det$key>
<p>
<ul>
<table cellpadding=3>
<tr>
<th align=left   valign=bottom>Date</th>
<th align=left   valign=bottom>Name</th>
<th align=left   valign=bottom>Place</th>
<th align=right  valign=bottom>Reg<br>Count</th>
<th align=right  valign=bottom>Rental<br>Max</th>
<th align=center valign=bottom>Rental<br>Status</th>
</tr>
$details{$key}
</table>
</ul>
</div>
EOH
        }
    }
    $content .= "</div>\n</body>\n";
    $c->res->output($content);
}

#
# what about a max for the event?
#
sub meetingplace_update : Local {
    my ($self, $c, $id) = @_;

    my $e = $c->stash->{event} = model($c, 'Event')->find($id);
    $c->stash->{meetingplace_table}
        = meetingplace_table($c, 0, $e->sdate, $e->edate, $e->bookings());
    $c->stash->{template} = "event/meetingplace_update.tt2";
}

sub meetingplace_update_do : Local {
    my ($self, $c, $id) = @_;

    my $e = model($c, 'Event')->find($id);
    my @cur_mps = grep {  s{^mp(\d+)}{$1}  }
                     keys %{$c->request->params};
    # delete all old bookings and create the new ones.
    model($c, 'Booking')->search(
        { event_id => $id },
    )->delete();
    for my $mp (@cur_mps) {
        model($c, 'Booking')->create({
            meet_id    => $mp,
            program_id => 0,
            rental_id  => 0,
            event_id   => $id,
            sdate      => $e->sdate,
            edate      => $e->edate,
        });
    }
    # show the event again - with the updated meeting places
    view($self, $c, $id);
    $c->forward('view');
}

1;
