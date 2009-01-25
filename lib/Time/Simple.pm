use strict;
use warnings;
package Time::Simple;

use Carp; 
use overload
    '-'    => 'diff',
    'bool' => sub { 1 }
    ;

my $error = "";
my $am_pm_convention = 1;       # the default
# 0   24 hour time: hours 1-11 are a.m., 12-23 are p.m.
# 1   hours 1-7 are really 13-19
#     hours 8-12 are a.m.
#     13-23 are p.m.
#     times are formatted in 12 hour syntax but without the a.m./p.m. suffix.
# 2   same as 1 except times are always formatted suffixed with a.m./p.m.
#


sub new {
    my ($class, $s) = @_;
    if ($s =~ m{^\s*(\d+)(?::(\d+))?\s*$}) {
        my ($hours, $mins) = ($1, $2);
        $mins |= 0;
        if ($hours > 23 || $mins > 59) {
            $error = "Invalid hours or minutes: $s";
            return;
        }
        if ($am_pm_convention && (1 <= $hours && $hours <= 7)) {
            $hours += 12;
        }
        return bless {
            minutes => $hours*60 + $mins,
        }, $class;
    }
    $error = "Illegal time syntax: $s";
    return;
}

sub am_pm_convention {
    my ($class) = shift;
    $am_pm_convention = shift;
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

sub format {
    my $self = shift;
    my $am_pm = shift || $am_pm_convention;     # can override the set default
    my $m = $self->{minutes};
    my $hour = int($m/60);
    if ($am_pm != 0 && $hour > 12) {
        $hour -= 12;
    }
    my $min  = $m%60;
    my $fmt = sprintf("%d:%02d", $hour, $min);
    if ($am_pm == 2) {
        $fmt .= (1 <= $hour && $hour <= 7)? " p.m."
                :                           " a.m."
                ;
    }
    $fmt;
}

sub hours {
    my ($self) = @_;
    return int($self->{minutes}/60);
}
sub minutes {
    my ($self) = @_;
    return $self->{minutes}%60;
}

1;
