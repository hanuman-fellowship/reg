use strict;
use warnings;
package RetreatCenter::Controller::Activity;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    slurp
    stash
    tt_today
/;

sub view : Local {
    my ($self, $c, $day, $temple) = @_;

    $temple ||= 0;
    if (! $day) {
        $day = tt_today($c)->format('%a');
    }
    my @days = qw/ Sun Mon Tue Wed Thu Fri Sat /;
    my ($prev, $next);
    for my $i (0 .. $#days) {
        if ($day eq $days[$i]) {
            $prev = $i-1 >=      0? $days[$i-1]: 'Sat';
            $next = $i+1 <= $#days? $days[$i+1]: 'Sun';
        }
    }
    if (! $prev) {
        # some nefarious person tried to force a non-day
        $prev = 'Sun';
        $next = 'Tue';
    }
    my $file = "/var/Reg/grab_new/$day";
    my @lines;
    if (-r $file) {
        @lines = split '\n', slurp($file);
    }
    else {
        @lines = ('Nothing happened on this day.');
    }
    if ($temple <= 1) {
        my $tmpl_re = qr{\A temple(?!\s+donation)}xms;
        if ($temple == 1) {
            @lines = grep { /$tmpl_re/ } @lines;
        }
        else {
            my $nbefore = @lines;
            @lines = grep { ! /$tmpl_re/ } @lines;
            my $ntemple = $nbefore - @lines;
            if ($lines[-1] =~ m{\A \*\*}xms) {
                # no need for a time
                pop @lines;
            }
            if ($ntemple) {
                push @lines, "<a href=/activity/view/$day/1>temple $ntemple</a>";
            }
        }
    }
    my $s = "";
    my $time;
    for my $l (@lines) {
        if ($l =~ m{\A \*\* \s (\d+:\d+)}xms) {
            $time = $1;
        }
        else {
            $s .= $l;
            $s .= " <span class=greyed>$time</span>" if $time;
            $time = "";
            $s .= "<br>";
        }
    }
    stash($c,
        prev     => $prev,
        next     => $next,
        date     => _full_day($day),
        output   => $s,
        template => 'activity/view.tt2',
    );
}

sub _full_day {
    my ($day) = @_;
    return $day . ($day eq 'Tue'? 's'
                  :$day eq 'Wed'? 'nes'
                  :$day eq 'Thu'? 'rs'
                  :$day eq 'Sat'? 'ur'
                  :               '') . 'day';
}

1;
