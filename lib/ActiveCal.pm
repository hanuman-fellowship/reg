use strict;
use warnings;
package ActiveCal;

use Date::Simple qw/
    today
    date
    days_in_month
/;
use DateRange;  # imports overlap
use Global qw/
    %string
/;
use List::Util qw/
    max
/;
use GD;

my $day_height = 40;    # 40

sub new {
    my ($class, $year, $month, $events_ref, $no_where_ord, $master_cal) = @_;

    my $day_width = $string{cal_day_width};
    my $today = today();
    if ($today->year == $year && $today->month == $month) {
        $today = $today->day;
    }
    else {
        $today = 0;
    }
    my $ndays = days_in_month($year, $month);
    my $first = date($year, $month, 1);
    my $last  = date($year, $month, $ndays);
    my $cal_width = $ndays*$day_width + 1;
        # we use +1 in the above line for the last vertical line
    #
    # we need to determine the height of the calendar
    #
    my $max = 3;        # always a certain height...
    if ($master_cal) {
        # events do not overlap, they stack.
        # the meeting places (i.e. bookings) do not matter.
        # we want to stack only when we must.
        #
        my $dr_cal = DateRange->new($first, $last);
        my @days = (0) x $ndays;
        for my $ev (@$events_ref) {
            if (my $dr = overlap($ev, $dr_cal)) {
                # needs some rethinking?
                my $d1 = $dr->sdate;
                my $d = ref $d1? $d1->day: date($d1)->day;
                my $e1 = $dr->edate;
                my $e = ref $e1? $e1->day: date($e1)->day;
                for my $d ($d .. $e) {
                    ++$days[$d];
                }
            }
        }
        $max = max($max, @days) - 1;
            # -1 for some reason - empirically derived.
            # many opportunities for off-by-one errors here
            # so I just keep fiddling until it works and then stop.
    }
    else {
        # meeting places help arrange the vertical
        #
        for my $ev (@$events_ref) {
            if ($first <= $ev->edate && $ev->sdate <= $last) {
                my $nbookings = 0;
                for my $bk ($ev->bookings) {
                    ++$nbookings;
                    my $ord = $bk->meeting_place->disp_ord;
                    if ($ord > $max) {
                        $max = $ord;
                    }
                }
                if (!$nbookings && $no_where_ord > $max) {
                    $max = $no_where_ord;
                }
            }
        }
    }
    my $cal_height = $max*40 + 70;     # 100???
    my $im = GD::Image->new($cal_width, $cal_height);
    my $white = $im->colorAllocate(255,255,255);    # 1st color = background
    my $red   = $im->colorAllocate(255,  0,  0);
    my $black = $im->colorAllocate(0,    0,  0);
    my $mon_thu = $im->colorAllocate($string{cal_mon_thu_color} =~ m{\d+}g);
    my $fri_sun = $im->colorAllocate($string{cal_fri_sun_color} =~ m{\d+}g);
    my $abutt   = $im->colorAllocate($string{cal_abutt_color} =~ m{\d+}g);
    # surrounding border
    $im->rectangle(0, 0, $cal_width-1, $cal_height-1, $black);

    my @day_name = qw/Su M Tu W Th F Sa/;
    my $dow = date($year, $month, 1)->day_of_week();
    for my $d (1 .. $ndays) {
        my $x = ($d-1) * $day_width;
        my $d_offset = ($d < 10)? 11: 7;
        my $name = $day_name[$dow];
        my $n_offset = (length($name) == 1)? 8: 4;
        # the above are sensitive to the day_width

        # vertical lines for the days of the month
        $im->line($x, 0, $x, $cal_height-1, $black) unless $d == 1;
            # if d == 1 the line is already there (surrounding border).

        # background colors for the different days
        $im->filledRectangle(
            $x+1, $day_height, $x+$day_width-1, $cal_height-2,
            ((1 <= $dow && $dow <= 4)? $mon_thu
             :                         $fri_sun)
        );

        # today is special
        if ($d == $today) {
            $im->filledRectangle(
                $x+1, 1, $x+$day_width, $day_height-1,
                $im->colorAllocate($string{cal_today_color} =~ m{\d+}g)
            );
        }
        # these offsets depend on the day height/width somehow...???
        $im->string(gdGiantFont, $x+$d_offset, 5, $d, $black);
        $im->string(gdGiantFont, $x+$n_offset+4, 20, $name,
                    (1 <= $dow && $dow <= 4)? $black: $red);
        $dow = ($dow+1) % 7;
    }
    # line underneath the day names - needed/wanted?
    if ($string{cal_day_line}) {
        $im->line(0, $day_height, $cal_width-1, $day_height, $black);
    }
    bless {
        image  => $im,
        sdate  => date($year, $month, 1),
        edate  => date($year, $month, $ndays),
        ndays  => $ndays,
        black  => $black,
        white  => $white,
        red    => $red,
        abutt  => $abutt,
        cal_width  => $cal_width,
        cal_height => $cal_height,
        counts => [],
        prs    => [],
        no_where_event_spans => [],
    }, $class;
}

# accessors
sub image { shift->{image}; }
sub sdate { shift->{sdate}; }
sub edate { shift->{edate}; }
sub black { shift->{black}; }
sub white { $_[0]->{white}; }
sub red   { $_[0]->{red  }; }
sub abutt { $_[0]->{abutt}; }
sub ndays { $_[0]->{ndays}; }

# return an array of keys
# for the hash of ActiveCal objects
# that the range [ $sdate, $edate ] falls in.
sub keys {
    my ($class, $sdate, $edate) = @_;

    my @keys;
    my $d = date($sdate->year, $sdate->month, 1);
    while ($d <= $edate) {
        push @keys, $d->format("%Y%m");

        # and on to the first of the next month
        $d += days_in_month($d->year, $d->month);
    }
    return @keys;
}

sub cal_height {
    my ($self) = @_;
    
    $self->{cal_height};
}

sub add_pr {
    my ($self, $sday, $eday, $pr) = @_;

    my $per = $pr->person;
    my $start = $pr->date_start_obj->day;
    my $end   = $pr->date_end_obj->day;
    my $name = $per->last . ", " . $per->first;
    my $id = $pr->id;
    for my $d ($sday .. $eday) {
        my $status = ($d == $start)? "arr"
                    :($d == $end  )? "lv"
                    :                "";
        $name =~ s{'}{&rsquo;}xmsg;  # for Charles O'Neill
        push @{$self->{prs}[$d]}, "$name\t$id\t$status";
        $self->{counts}[$d]++;
    }
}

#
# return the array of people who
# have a PR on the given day
# it may be undef.
#
sub get_prs {
    my ($self, $d) = @_;

    $self->{prs}[$d];
}

# we have an event on the top row in the line segment [ $x1, $x2].
sub no_where_add {
    my ($self, $x1, $x2) = @_;
    push @{$self->{no_where_event_spans}}, [ $x1, $x2 ];
}

# are there any events on the top row that overlap
# the line segment [ $s1, $e1 ]?
sub no_where_overlaps {
    my ($self, $s1, $e1) = @_;

    for my $aref (@{$self->{no_where_event_spans}}) {
        my $s2 = $aref->[0];
        my $e2 = $aref->[1];
        my $max_s = ($s1 > $s2)? $s1: $s2;
        my $min_e = ($e1 > $e2)? $e2: $e1;
        if ($max_s < $min_e) {
            return 1;
        }
    }
    return 0;
}

# a program or a rental has people present
# from $start_day to $end_day.
sub add_count {
    my ($self, $start_day, $end_day, $count) = @_;
open JON, '>>/tmp/jon'; print JON "$start_day .. $end_day adding $count\n"; close JON;
    return if ! $count;
    for my $d ($start_day .. $end_day) {
        $self->{counts}[$d] += $count;
    }
}

sub get_count {
    my ($self, $d) = @_;
    return $self->{counts}[$d] || 0;
}

1;
