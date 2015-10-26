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
    my ($self, $c, $day) = @_;

    if (! $day) {
        $day = tt_today($c)->format('%a');
    }
    my @days = qw/ Sun Mon Tue Wed Thu Fri Sat /;
    while ($days[0] ne $day) {
        unshift @days, pop @days;
    }
    my $prev = $days[-1];
    my $next = $days[1];
    my @lines = split '\n', slurp("root/static/grab_new/$day");
    my $s = "";
    my $time;
    for my $l (@lines) {
        if ($l =~ m{\*\* \s (\d+:\d+)}xms) {
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
