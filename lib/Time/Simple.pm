=comment
Times

They are more complex than they appear.
Dates, too.

- In the database they are stored in 4 digit 24 hour/military time.
    This makes the SQL clause 'order by' possible.
- To enter a time there is a variety of flexible formats:
    1423
    2:23
    2:23 pm
    223
- For display there are 3 methods t24(), t12(), and ampm().
    t12 and ampm take an optional parameter to say that
    you want to truncate a possible :00.
- The internal form of the object is in minutes since midnight
    to facilitate time difference calculations.  Otherwise
    determining the number of minutes between 11:30 am and
    7:25 pm is tricky - or between 1130 and 1925.
    Time comparisions would have been easy if we had stored in 24 hour time
    but not differences.

=cut
use strict;
use warnings;
package Time::Simple;

use base 'Exporter';
our @EXPORT_OK = qw/
    get_time
/;

use Carp; 
use overload
    '-'    => '_diff',      # minutes between two times
    'bool' => sub { 1 },    # needed for some reason
    '<=>'  => '_compare',
    '""'   => 'format',     # stringification using the current format
    ;

our $error = "";

#
# be very flexible in what you accept as a valid time.
# all of these are okay:
#
# 0104      = 1:04 am
# 2104      = 9:04 pm
# 1         = 1:00 pm
# 245       = 2:45 pm
# 3:23      = 3:23 pm
# 8:23      = 8:23 am
# 7:23      = 7:23 pm
# 9:04      = 9:04 am
# 11:00 pm  = 11:00 pm
# 2 a       = 2:00 am
# 908pm     = 9:08 pm
# 10:09 p.m. = 10:09 pm
# (empty)    = current time - i.e. NOW
# 1 3        = 1:03 pm
# 2 34 p     = 2:34 pm
# 2 mmmmm... = 2:00 pm
# 2310 pm    = illegal
#
sub get_time {
    my $class = (@_ == 2)? shift
                :          'Time::Simple';
    my $s = shift || "";
    my $orig_s = $s;

    my ($hours, $mins);

    $s =~ s{^\s*|\s*$}{}g;
    $s =~ s{\s*[m.]+$}{}i;
    my $ampm = "";
    if ($s =~ s{\s*([ap])$}{}i) {
        $ampm = lc $1;
    }
    if ($s eq '') {
        if ($ampm) {
            $error = "Inappropriate am/pm suffix: $orig_s";
            return;
        }
        ($hours, $mins) = (localtime())[2,1];
    }
    elsif ($s =~ m{^\d{4}$}) {
        if ($ampm) {
            $error = "No am/pm suffix allowed with 24 hour time: $orig_s";
            return;
        }
        $hours = substr($s, 0, 2);
        $mins  = substr($s, 2, 2);
    }
    else {
        # not in 24 hour format so we need
        # to wonder about am/pm...  $hours _may_
        # need to have 12 added to it.
        #
        # first get the hours & minutes
        #
        if (   $s =~ m{^(\d+):(\d+)$}
            || $s =~ m{^(\d+)\s+(\d+)$}
        ) {
            $hours = $1;
            $mins = $2;
        }
        elsif ($s =~ m{^\d{3}$}) {
            $hours = substr($s, 0, 1);
            $mins  = substr($s, 1, 2);
        }
        elsif ($s =~ m{^\d{1,2}$}) {
            $mins = 0;
            $hours = $s;
        }
        else {
            $error = "Illegal time format: $orig_s";
            return;
        }
        if ($ampm eq 'a') {
            if ($hours == 12) {
                $hours = 0;
            }
        }
        elsif ($ampm eq 'p') {
            if (1 <= $hours && $hours <= 11) {
                $hours += 12;
            }
        }
        else {
            # convenient syntax for the normal times
            # of 8 am - 7 pm.
            #
            # one cannot achieve early morning
            # or late evening times this way.
            #
            if (1 <= $hours && $hours <= 7) {
                $hours += 12;
            }
        }
    }
    if ($hours > 23) {
        $error = "Invalid hours: $orig_s";
        return;
    }
    if ($mins > 59) {
        $error = "Invalid minutes: $orig_s";
        return;
    }
    return bless {
        minutes => $hours*60 + $mins,
    }, $class;
}

sub error {
    my ($class) = @_;
    return $error;
}

sub _diff {
    my ($self, $time2) = @_;
    if (! $time2->isa('Time::Simple')) {
        croak "Cannot subtract a non-Time::Simple object";
    }
    return $self->{minutes} - $time2->{minutes};
}

my $time_format = 'ampm';       # normal in U.S.A.

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
# 24   24 hour time
# 12   hours 1-7 are really 13-19
#      hours 8-12 are a.m.
#      13-23 are p.m.
#      times are formatted in 12 hour syntax but without the a.m./p.m. suffix.
#      early morning and late evening times cannot be shown unambiguously.
# ampm 12 hour time with a.m./p.m.
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
    if ($hours == 0) {
        $hours = 12;
    }
    elsif ($hours > 12) {
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

    return ($reverse ? $right->{minutes} <=>  $left->{minutes}
           :            $left->{minutes} <=> $right->{minutes});
}

sub ampm {
    my ($self, $trunc) = @_;
    my $s = $self->format('ampm');
    if ($trunc) {
        $s =~ s{:00}{};
    }
    $s;
}
sub t12 {
    my ($self, $trunc) = @_;
    my $s = $self->format('12');
    if ($trunc) {
        $s =~ s{:00}{};
    }
    $s;
}
sub t24 {
    my ($self) = @_;
    return $self->format('24');
}

1;
