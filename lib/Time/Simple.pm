use strict;
use warnings;
package Time::Simple;

use Carp; 
use overload
    '-'    => 'diff',
    'bool' => sub { 1 },
    '<=>'  => '_compare',
    '""'   => 'format',
    ;

my $error = "";

#
# input format:
# no need for am/pm suffix
# with 1 or 2 digits or with a colon you get normal times 8:00 am to 7:59 pm
# otherwise 4 digits are required.
#
# 0104      = 1:04 am
# 2104      = 9:04 pm
# 1         = 1:00 pm
# 3:23      = 3:23 pm
# 8:23      = 8:23 am
# 7:23      = 7:23 pm
# 9:04      = 9:04 am

sub new {
    my ($class, $s) = @_;
    $s =~ s{^\s*|\s*$}{}g;
    if ($s =~ m{^(\d+)(?::(\d+))?$}) {
        my ($hours, $mins) = ($1, $2);
        if (length($hours) == 4) {
            $mins  = substr($hours, 2, 2);
            $hours = substr($hours, 0, 2);
        }
        elsif (1 <= $hours && $hours <= 7) {
            $hours += 12;
        }
        $mins ||= 0;
        if ($hours > 23 || $mins > 59) {
            $error = "Invalid hours or minutes: $s";
            return;
        }
        return bless {
            minutes => $hours*60 + $mins,
        }, $class;
    }
    $error = "Illegal time syntax: $s";
    return;
}

sub error {
    my ($class) = @_;
    return $error;
}

sub diff {
    my ($self, $time2) = @_;
    if (ref($time2) ne "Time::Simple") {
        croak "Cannot subtract a non-Time::Simple object";
    }
    return $self->{minutes} - $time2->{minutes};
}

my $time_format = 12;

#
# 24, 12 (default), or 'ampm'
#
sub set_format {
    my ($class) = shift;
    $time_format = shift;
        # check it
}

#
# output format:
#
# 0   24 hour time
# 1   hours 1-7 are really 13-19
#     hours 8-12 are a.m.
#     13-23 are p.m.
#     times are formatted in 12 hour syntax but without the a.m./p.m. suffix.
# 2   12 hour time with a.m./p.m.
#
sub format {
    my $self = shift;
    my $fmt = shift || $time_format;     # can override the set default
        # check it
    my $m = $self->{minutes};
    my $hours = int($m/60);
    my $mins  = $m % 60;

    if ($fmt eq '24') {
        return sprintf("%02d%02d", $hours, $mins);
    }

    # 12 hour format - with or without a.m./p.m.
    my $suffix = "";
    if ($fmt eq 'ampm') {
        $suffix = ($hours >= 12)? " pm": " am";
    }
    if ($hours > 12) {
        $hours -= 12;
    }
    return sprintf("%d:%02d", $hours, $mins) . $suffix;
}

sub hours {
    my ($self) = @_;
    return int($self->{minutes}/60);
}
sub minutes {
    my ($self) = @_;
    return $self->{minutes}%60;
}

sub _compare {
    my ($left, $right, $reverse) = @_;

    return ($reverse ? $right->{minutes} <=> $left->{minutes}
           :           $left->{minutes}  <=> $right->{minutes});
}

1;
