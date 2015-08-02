use strict;
use warnings;
package HLog;

use base 'Exporter';
our @EXPORT = qw/
    hlog
    hlog_toggle
/;
use FileHandle;

my $fh;
BEGIN {
    open $fh, ">>", "hlog" or die "no hlog: $!";
    $fh->autoflush(1);
}

sub hlog {
    my ($c,
        $name, $the_date,
        $action,
        $h_id, $curmax, $cur, $sex,
        $p_id, $r_id,
        $note) = @_;

    my $user = $c->user->username();
    my ($sec, $min, $hour, $mday, $month) = localtime;
    ++$month;
    printf {$fh} "%-8s %8s %-9s %3d %d %d %s %4d %4d "
                 . "%2d/%2d %02d:%02d %s $note\n",
                 $name, $the_date, $action,
                 $h_id, $curmax, $cur, $sex,
                 $p_id, $r_id,
                 $month, $mday, $hour, $min,
                 $user
                 ;
}

sub hlog_toggle {
    my ($c, $state) = @_;

    my ($sec, $min, $hour, $mday, $month) = localtime;
    my $user = $c->user->username();
    printf {$fh} "%2d/%2d %02d:%02d %s Logging %s\n",
                 $month, $mday, $hour, $min,
                 $user,
                 ($state == 1? "ON": "OFF")
                 ;
}

1;
