#
# Date::Simple - a simple date object
#
package Date::Simple;

$VERSION = '3.01';
use Exporter ();
@ISA = ('Exporter');
@EXPORT_OK = qw/ today  ymd  d8  date  leap_year  days_in_month /;
%EXPORT_TAGS = (all => \@EXPORT_OK);

use strict;
use Carp ();
use overload
    '+'   => '_add',
    '-'   => '_subtract',
    '=='  => '_eq',
    '!='  => '_ne',
    '<=>' => '_compare',
    'eq'  => '_eq',
    'ne'  => '_ne',
    'cmp' => '_compare',
    'bool' => sub { 1 },
    '""'  => '_stringify';

sub today {
    my ($d, $m, $y) = (localtime)[3..5];
    $y += 1900;
    $m += 1;
    return ymd($y, $m, $d, @_);   # any arg is format
}

sub _inval {
    my ($first);
    $first = shift;
    Carp::croak ("Invalid ".
                 (ref($first)||$first).
                 " constructor args: ('".
                 join("', '", @_)."')"
                );
}

sub _new {
    my ($that, @ymd) = @_;
    my ($class);

    $class = ref ($that) || $that;

    my $format = "%Y-%m-%d";                        # default format
    $format = pop @ymd if scalar(@ymd) % 2 == 0;    # last arg may be format

    if (scalar (@ymd) == 1) {
        my $x = $ymd[0];
        if (ref ($x) eq 'ARRAY') {
            @ymd = @$x;
        } elsif (UNIVERSAL::isa($x, $class)) {
            return ($x);
        } elsif ($x =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/
               || $x =~ /^(\d\d\d\d)(\d\d)(\d\d)$/)
        {
            @ymd = ($1, $2, $3);
        } else {
            return (undef);
        }
    }
    if (scalar (@ymd) == 0) {
        return (today());
    }
    if (scalar (@ymd) == 3) {
        my $days = ymd_to_days (@ymd);
        return undef if ! defined ($days);
        return bless {
            days   => $days,
            "format" => $format,
        }, $class;
    }
    _inval ($class, @ymd);
}

sub date {
    return (scalar (_new (__PACKAGE__, @_)));
}

# Same as date() but it's a method and croaks on error if called with
# one arg.
sub new {
    my ($date);

    $date = &_new;
    if (! $date && scalar (@_) == 1) {
        Carp::croak ("'" . shift() . "' is not a valid ISO formated date");
    }
    return ($date);
}

sub next { return ($_[0] + 1); }
sub prev { return ($_[0] - 1); }

sub _gmtime {
        my ($self) = @_;
    my ($y, $m, $d) = days_to_ymd ($self->{days});
    $y -= 1900;
    $m -= 1;
    return (0, 0, 0, $d, $m, $y);
}

sub set_format {
    my $self = shift;
    $self->{"format"} = shift;
	return $self;
}

sub get_format {
    return shift->{"format"};
}

sub format {
    my ($self, $format) = @_;
    return "$self" unless defined ($format);
    require POSIX;
    local $ENV{TZ} = 'UTC+0';
    return POSIX::strftime ($format, _gmtime ($self));
}

sub strftime { &format }

sub ymd {
    my $format = "%Y-%m-%d";
    $format = pop if @_ == 4;
    my $days = &ymd_to_days;
    return undef unless defined ($days);
    return bless {        
        days   => $days,
        "format" => $format,
    }, __PACKAGE__;
}

sub d8 {
    my $d8 = shift;
    my @ymd = $d8 =~ m/^(\d{4})(\d\d)(\d\d)$/ or return undef;
    return ymd(@ymd, @_);   # may have a format argument
}

# Precise integer arithmetic functions unfortunately missing from
# Perl's core:

sub _divmod {
    my ($quot, $int);

    $quot = $_[0] / $_[1];
    $int = int($quot);
    $int -= 1 if $int > $quot;
    $_[0] %= $_[1];
    return $int;
};

sub _div {
    my ($quot, $int);

    $quot = $_[0] / $_[1];
    $int = int($quot);
    return $int - 1 if $int > $quot;
    return $int;
};

sub leap_year {
    my $y = shift;
    $y = $y->year if ref $y;    # called as method or with date obj as param
    return (($y%4==0) and ($y%400==0 or $y%100!=0)) || 0;
}

my @days_in_month = (
 [0,31,28,31,30,31,30,31,31,30,31,30,31],
 [0,31,29,31,30,31,30,31,31,30,31,30,31],
);

sub days_in_month($;$) {
    my ($y, $m) = @_;
    ($y, $m) = ($y->year, $y->month) if ref $y;     # called as method
                                                # or with date obj as param
    return $days_in_month[leap_year($y)][$m];
}

sub validate ($$$) {
    my ($y, $m, $d)= @_;
    # any +ve integral year is valid
    return 0 if $y != abs int $y;
    return 0 unless 1 <= $m and $m <= 12;
    return 0 unless 1 <= $d and $d <= $days_in_month[leap_year($y)][$m];
    return 1;
}

# Given a year, month, and day, return the canonical day number.
# That is the number of days since 1 January 1970, negative if earlier.
sub ymd_to_days {
    my ($Y, $M, $D) = @_;
    my ($days, $x);

    if ($M < 1 || $M > 12 || $D < 1 ||
        ($D > 28 && $D > days_in_month($Y, $M)))
    {
        return undef;
    }

    $days = $D +
        (undef, -1, 30, 58, 89, 119, 150, 180, 211, 242, 272, 303, 333)[$M];
    $days += 365 * ($Y - 1970);
    $x = ($M <= 2 ? $Y-1 : $Y);
    $days += _div (($x - 1968), 4);
    $days -= _div (($x - 1900), 100);
    $days += _div (($x - 1600), 400);
    return $days;
}

sub days_since_1970 { ${$_[0]} }

# Given a canonical day number (days since 1 Jan 1970), return the
# year, month, and day.
sub days_to_ymd {
    my ($days) = @_;
    my ($year, $mnum, $mday, $tmp);

    # Shift frame of reference from 1 Jan 1970 to (the imaginary) 1 Mar 0AD.
    $tmp = $days + 719468;

    # Do the math.
    $year = 400 * _divmod ($tmp, 146097);
    if ($tmp == 146096) {
        # Handle 29 Feb 2000, 2400, ...
        $year += 400;
        $mnum = 2;
        $mday = 29;
    } else {
        $year += 100 * _divmod ($tmp, 36524);
        $year += 4 * _divmod ($tmp, 1461);
        if ($tmp == 1460) {
            $year += 4;
            $mnum = 2;
            $mday = 29;
        } else {
            $year += _divmod ($tmp, 365);
            $mnum = _divmod ($tmp, 31);
            $mday = $tmp + (1, 1, 2, 2, 3, 3, 3, 4, 4, 5, 5, 5)[$mnum];
            $tmp = (31, 30, 31, 30, 31, 31, 30, 31, 30, 31, 31, 28)[$mnum];
            if ($mday > $tmp) {
                $mday -= $tmp;
                $mnum += 1;
            }
            if ($mnum > 9) {
                $mnum -= 9;
                $year += 1;
            } else {
                $mnum += 3;
            }
        }
    }
    return ($year, $mnum, $mday);
}

sub as_ymd { return days_to_ymd ($_[0]->{days}); }
sub as_d8  { return sprintf ("%04d%02d%02d", &as_ymd); }

sub year  { return (&as_ymd) [0]; }
sub month { return (&as_ymd) [1]; }
sub day   { return (&as_ymd) [2]; }

sub day_of_week {
    return ((${$_[0]} + 4) % 7);
}

#------------------------------------------------------------------------------
# the following methods are called by the overloaded operators, so they should
# not normally be called directly.
#------------------------------------------------------------------------------
sub _stringify {
        my $self = shift;
        if ($self->{"format"}) {
                $self->format($self->{"format"});
        } else {
                return sprintf ("%04d-%02d-%02d", as_ymd($self));
        }
}

sub _add {
    my ($date, $diff) = @_;

    if ($diff !~ /^-?\d+$/) {
        Carp::croak ("Date interval must be an integer");
    }
    return bless {
        days   => ($date->{days} + $diff),
        "format" => $date->{"format"},
    },  ref($date)
}

sub _subtract {
    my ($left, $right, $reverse) = @_;

    if ($reverse) {
        Carp::croak ("Can't subtract a date from a non-date");
    }
    if (ref($right) eq '' && $right =~ /^-?\d+$/) {
        return bless {
            days   => ($left->{days} - $right),
            "format" => $left->{"format"},
        }, ref($left);
    }
    return ($left->{days} - $right->{days});
}

sub _compare {
    my ($left, $right, $reverse) = @_;

    $right = $left->new($right) || _inval ($left, $right);
    return ($reverse ? $right->{days} <=> $left->{days}:
                               $left->{days}  <=> $right->{days});
}

sub _eq {
    my ($left, $right) = @_;
    return (($right = $left->_new($right)) && $right->{days} == $left->{days});
}

sub _ne {
    return (!&_eq);
}

1;

=head1 NAME

Date::Simple - a simple date object

=head1 SYNOPSIS

    use Date::Simple ('date', 'today');

    # Difference in days between two dates:
    $diff = date('2001-08-27') - date('1977-10-05');

    # Offset $n days from now:
    $date = today() + $n;
    print "$date\n";  # uses ISO 8601 format (YYYY-MM-DD)

    use Date::Simple ();
    my $date  = Date::Simple->new('1972-01-17');
    my $year  = $date->year;
    my $month = $date->month;
    my $day   = $date->day;

    use Date::Simple (':all');
    my $date2 = ymd($year, $month, $day);
    my $date3 = d8('19871218');
    my $today = today();
    my $tomorrow = $today + 1;
    if ($tomorrow->year != $today->year) {
        print "Today is New Year's Eve!\n";
    }

    if ($today > $tomorrow) {
        die "warp in space-time continuum";
    }

    print "Today is ";
    print(('Sun','Mon','Tues','Wednes','Thurs','Fri','Satur')
          [$today->day_of_week]);
    print "day.\n";

    # you can also do this:
    ($date cmp "2001-07-01")
    # and this
    ($date <=> [2001, 7, 1])

=begin text

INSTALLATION

 If your system has the "make" program or a clone:

     perl Makefile.PL
     make
     make test
     make install

 If you lack "make", copy the "lib/Date" directory to your module
 directory (run "perl -V:sitelib" to find it).

 If "make test" fails, perhaps it means your system can't compile C
 code.  Try:

     make distclean
     perl Makefile.PL noxs
     make
     make test
     make install

 This will use the pure-Perl implementation.

=end text

=head1 DESCRIPTION

Dates are complex enough without times and timezones.  This module may
be used to create simple date objects.  It handles:

=over 4

=item Validation.

Reject 1999-02-29 but accept 2000-02-29.

=item Interval arithmetic.

How many days were between two given dates?  What date comes N days
after today?

=item Day-of-week calculation.

What day of the week is a given date?

=back

It does B<not> deal with hours, minutes, seconds, and time zones.

A date is uniquely identified by year, month, and day integers within
valid ranges.  This module will not allow the creation of objects for
invalid dates.  Attempting to create an invalid date will return
undef.  Month numbering starts at 1 for January, unlike in C and Java.
Years are 4-digit.

Gregorian dates up to year 9999 are handled correctly, but we rely on
Perl's builtin C<localtime> function when the current date is
requested.  On some platforms, C<localtime> may be vulnerable to
rollovers such as the Unix C<time_t> wraparound of 18 January 2038.

Overloading is used so you can compare or subtract two dates using
standard numeric operators such as C<==>, and the sum of a date object
and an integer is another date object.

Date::Simple objects are immutable.  After assigning C<$date1> to
C<$date2>, no change to C<$date1> can affect C<$date2>.  This means,
for example, that there is nothing like a C<set_year> operation, and
C<$date++> assigns a new object to C<$date>.

This module contains various undocumented functions.  They may not be
available on all platforms and are likely to change or disappear in
future releases.  Please let the author know if you think any of them
should be public.

=cut

=head1 CONSTRUCTORS

Several functions take a string or numeric representation and generate
a corresponding date object.  The most general is C<new>, whose
argument list may be empty (returning the current date), a string in
format YYYY-MM-DD or YYYYMMDD, a list or arrayref of year, month, and
day number, or an existing date object.

=over 4

=item Date::Simple->new ([ARG, ...])

=item date ([ARG, ...])

    my $date = Date::Simple->new('1972-01-17');

The C<new> method will return a date object if the values passed in
specify a valid date.  (See above.)  If an invalid date is passed, the
method returns undef.  If the argument is invalid in form as opposed
to numeric range, C<new> dies.

The C<date> function provides the same functionality but must be
imported or qualified as C<Date::Simple::date>.  (To import all public
functions, do C<use Date::Simple (':all');>.)  This function returns
undef on all invalid input, rather than dying in some cases like
C<new>.

=item today()

Returns the current date according to C<localtime>.

B<Caution:> To get tomorrow's date (or any fixed offset from today),
do not use C<today + 1>.  Perl parses this as C<today(+1)>.  You need
to put empty parentheses after the function: C<today() + 1>.

=item ymd (YEAR, MONTH, DAY)

Returns a date object with the given year, month, and day numbers.  If
the arguments do not specify a valid date, undef is returned.

Example:

    use Date::Simple ('ymd');
    $pbd = ymd(1987, 12, 18);

=item d8 (STRING)

Parses STRING as "YYYYMMDD" and returns the corresponding date object,
or undef if STRING has the wrong format or specifies an invalid date.

Example:

    use Date::Simple ('d8');
    $doi = d8('17760704');

Mnemonic: The string matches C</\d{8}/>.  Also, "d8" spells "date", if
8 is expanded phonetically.

=back

=head1 INSTANCE METHODS

=over 4

=item DATE->next

    my $tomorrow = $today->next;

Returns an object representing tomorrow.

=item DATE->prev

    my $yesterday = $today->prev;

Returns an object representing yesterday.

=item DATE->year

    my $year  = $date->year;

Return the year of DATE as an integer.

=item DATE->month

    my $month = $date->month;

Return the month of DATE as an integer from 1 to 12.

=item DATE->day

    my $day   = $date->day;

Return the DATE's day of the month as an integer from 1 to 31.

=item DATE->day_of_week

Return a number representing DATE's day of the week from 0 to 6, where
0 means Sunday.

=item DATE->as_ymd

    my ($year, $month, $day) = $date->as_ymd;

Returns a list of three numbers: year, month, and day.

=item DATE->as_d8

Returns the "d8" representation (see C<d8>), like
C<$date-E<gt>format("%Y%m%d")>.

=item DATE->format (STRING)

=item DATE->strftime (STRING)

These functions are equivalent.  Return a string representing the
date, in the format specified.  If you don't pass a parameter, an ISO
8601 formatted date is returned.

    my $change_date = $date->format("%d %b %y");
    my $iso_date1 = $date->format("%Y-%m-%d");
    my $iso_date2 = $date->format;

The formatting parameter is similar to one you would pass to
strftime(3).  This is because we actually do pass it to strftime to
format the date.  This may result in differing behavior across
platforms and locales and may not even work everywhere.

=back

=head1 OPERATORS

Some operators can be used with Date::Simple instances.  If one side
of an expression is a date object, and the operator expects two date
objects, the other side is interpreted as C<date(ARG)>, so an array
reference or ISO 8601 string will work.

=over 4

=item DATE + NUMBER

=item DATE - NUMBER

You can construct a new date offset by a number of days using the C<+>
and C<-> operators.

=item DATE1 - DATE2

You can subtract two dates to find the number of days between them.

=item DATE1 == DATE2

=item DATE1 < DATE2

=item DATE1 <=> DATE2

=item DATE1 cmp DATE2

=item etc.

You can compare two dates using the arithmetic or string comparison
operators.  Equality tests (C<==> and C<eq>) return false when one of
the expressions can not be converted to a date.  Other comparison
tests die in such cases.  This is intentional, because in a sense, all
non-dates are not "equal" to all dates, but in no sense are they
"greater" or "less" than dates.

=item DATE += NUMBER

=item DATE -= NUMBER

You can increment or decrement a date by a number of days using the +=
and -= operators.  This actually generates a new date object and is
equivalent to C<$date = $date + $number>.

=item "$date"

You can interpolate a date instance directly into a string, in the
format specified by ISO 8601 (eg: 2000-01-17).

You can specify a different date format for string interpolation
by giving it as an additional parameter to the constructors
today, date, d8, ymd, and new.   See the format/strftime method 
for details on the format string.

Doing arithmetic on a date object will not change its associated format.

If needed, there are also accessor methods set_format and get_format.

=back

=head1 UTILITIES

=over 4

=item leap_year (YEAR)

Returns true if YEAR is a leap year.

This can also be called as a method on a date object
or with a date object as a parameter.

=item days_in_month (YEAR, MONTH)

Returns the number of days in MONTH, YEAR.

This can also be called as a method on a date object
or with a date object as the only parameter.

=back

=head1 AUTHOR

    Marty Pauley <marty@kasei.com>
    John Tobey <jtobey@john-edwin-tobey.org>

=head1 COPYRIGHT

      Copyright (C) 2001  Kasei
      Copyright (C) 2001,2002 John Tobey.

      This program is free software; you can redistribute it and/or
      modify it under the terms of either:

      a) the GNU General Public License;
         either version 2 of the License, or (at your option) any later
         version.  You should have received a copy of the GNU General
         Public License along with this program; see the file COPYING.
         If not, write to the Free Software Foundation, Inc., 59
         Temple Place, Suite 330, Boston, MA 02111-1307 USA

      b) the Perl Artistic License.

      This program is distributed in the hope that it will be useful,
      but WITHOUT ANY WARRANTY; without even the implied warranty of
      MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut
