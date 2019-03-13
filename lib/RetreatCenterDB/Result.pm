use strict;
use warnings;

package RetreatCenterDB::Result;

use base 'DBIx::Class::Core';
use Time::Simple qw/
    get_time
/;

sub _get_as_time_obj {
    my ($self, $time_string) = @_;
    my $time_obj = get_time($time_string);
    if(!$time_obj) {
        die "The string $time_string cannot be parsed into a Time::Simple object";
    }
    return $time_obj;
}

1;

