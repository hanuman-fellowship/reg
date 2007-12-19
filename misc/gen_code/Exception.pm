#!/local/bin/perl -w
package Exception;
use strict;

use Exporter;
use vars '@ISA', '@EXPORT_OK';
@ISA = qw/Exporter/;
@EXPORT_OK = qw/except/;

use Util qw/slurp/;

my %exceptions;

#
# get the exceptions
#
open IN, "config/exceptions.txt"
	or die "cannot open config/exceptions.txt: $!\n";
my ($pname, $field, $val);
while (<IN>) {
	next if /^#/;
	next unless /\S/;
	chomp;
	($pname, $field, $val) = split /\t+/;
	if ($val =~ /file\s+(.*)/) {
		$val = slurp $1;
	}
	$exceptions{"$pname-$field"} = $val;
}
close IN;

sub except {
	my ($name, $method) = @_;
	return $exceptions{"$name-$method"};
}

1;
