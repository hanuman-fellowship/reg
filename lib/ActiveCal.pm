use strict;
use warnings;
package ActiveCal;

use Date::Simple qw/
    today
    date
    days_in_month
/;
use Lookup;
use GD;

my $day_width = 30;
my $day_height = 40;

sub new {
    my ($class, $year, $month, $events_ref) = @_;

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
    my $max = 3;        # always a certain height...
    for my $ev (@$events_ref) {
        if ($first <= $ev->edate && $ev->sdate <= $last) {
            for my $bk ($ev->bookings) {
                my $ord = $bk->meeting_place->disp_ord;
                if ($ord > $max) {
                    $max = $ord;
                }
            }
        }
    }
    my $cal_height = $max*40 + 70;     # 100???
    my $im = GD::Image->new($cal_width, $cal_height);
    my $white = $im->colorAllocate(255,255,255);    # 1st color = background
    my $red   = $im->colorAllocate(255,  0,  0);
    my $black = $im->colorAllocate(0,    0,  0);
    my $mon_thu = $im->colorAllocate($lookup{mon_thu_color} =~ m{\d+}g);
    my $fri_sun = $im->colorAllocate($lookup{fri_sun_color} =~ m{\d+}g);
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
                $im->colorAllocate($lookup{today_color} =~ m{\d+}g)
            );
        }
        # these offsets depend on the day height/width somehow...???
        $im->string(gdGiantFont, $x+$d_offset, 5, $d, $black);
        $im->string(gdGiantFont, $x+$n_offset+4, 20, $name,
                    (1 <= $dow && $dow <= 4)? $black: $red);
        $dow = ($dow+1) % 7;
    }
    $im->line(0, $day_height, $cal_width-1, $day_height, $black);
    bless {
        image  => $im,
        sdate  => date($year, $month, 1),
        edate  => date($year, $month, $ndays),
        ndays  => $ndays,
        black  => $black,
        white  => $white,
        red    => $red,
        cal_width  => $cal_width,
        cal_height => $cal_height,
        counts => [],
        prs    => [],
    }, $class;
}

# accessors
sub image { shift->{image}; }
sub sdate { shift->{sdate}; }
sub edate { shift->{edate}; }
sub black { shift->{black}; }
sub white { $_[0]->{white}; }
sub red   { $_[0]->{red  }; }
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

# return class constants
sub day_width {
    my ($class) = @_;
    
    $day_width;
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

1;
