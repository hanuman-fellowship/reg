use strict;
use warnings;
package ActiveCal;

use Date::Simple qw/
    date
    days_in_month
/;
use GD;

my $day_width = 27;
my $cal_height = 310;

sub new {
    my ($class, $year, $month) = @_;

    my $ndays = days_in_month($year, $month);
    my $cal_width = $ndays*$day_width + 1;
        # +1 above for the last vertical line
    my $im = GD::Image->new($cal_width, $cal_height);
    my $white = $im->colorAllocate(255,255,255);    # 1st color = background
    my $red   = $im->colorAllocate(255,  0,  0);
    my $black = $im->colorAllocate(0,    0,  0);
    # surrounding border
    $im->rectangle(0, 0, $cal_width-1, $cal_height-1, $black);

    my @day_name = qw/Su M Tu W Th F Sa/;
    my $dow = date($year, $month, 1)->day_of_week();
    for my $d (1 .. $ndays) {
        my $x = ($d-1) * $day_width;
        my $d_offset = ($d < 10)? 9: 5;
        my $name = $day_name[$dow];
        my $n_offset = (length($name) == 1)? 9: 5;

        $im->line($x, 0, $x, $cal_height-1, $black);
        $im->string(gdLargeFont, $x+$d_offset, 5, $d, $black);
        $im->string(gdLargeFont, $x+$n_offset, 20, $name,
                    (1 <= $dow && $dow <= 4)? $black: $red);
        $dow = ($dow+1) % 7;
    }
    $im->line(0, 40, $cal_width-1, 40, $black);
    my $last = $ndays * $day_width;
    bless {
        image => $im,
        sdate => date($year, $month, 1),
        edate => date($year, $month, $ndays),
        black => $black,
        white => $white,
        red   => $red,
    }, $class;
}

# accessors
sub image { shift->{image}; }
sub sdate { shift->{sdate}; }
sub edate { shift->{edate}; }
sub black { shift->{black}; }
sub white { $_[0]->{white}; }
sub red   { $_[0]->{red  }; }

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

# return class constant
sub day_width {
    my ($class) = @_;
    
    $day_width;
}

1;
