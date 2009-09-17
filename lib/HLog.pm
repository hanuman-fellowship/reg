use strict;
use warnings;
package HLog;

use base 'Exporter';
our @EXPORT = qw/
    hlog
/;
use FileHandle;

my $fh;
BEGIN {
    open $fh, ">>", "/tmp/hlog" or die "no hlog: $!";
    $fh->autoflush(1);
}

sub hlog {
    my ($c, $msg) = @_;

    my $user = $c->user->username();
    my ($sec, $min, $hour, $mday, $month) = localtime;
    ++$month;
    printf {$fh} "%02d/%02d %02d:%02d %s %s\n",
                 $mday, $month, $hour, $min,
                 $user,
                 $msg;
}
