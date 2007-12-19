package Housing;
use strict;

my %housing;
use vars '%valid_types';

BEGIN {
	%valid_types = (
		 "unknown"	 => 1,
		 "commuting" => 2,
		 "own tent"	 => 3,
		 "own van"	 => 4,
		 "center tent"	 => 5,
		 "economy"	 => 6,
		 "dormitory" => 7,
		 "quad"	     => 8,
		 "triple"	 => 9,
		 "double"	 => 10,
		 "double bath"	 => 11,
		 "single"	     => 12,
		 "single bath"	 => 13,
	);

	open IN, "housing.tmp" or die "cannot open housing.tmp: $!\n";
	my ($num, $type, $cost);
	while (<IN>) {
		s/\cM\n$//;
		next unless /\S/;
		next if /^#/;
		($num, $type, $cost) = split /\t/;
		die "illegal type at line $.: $type\n"
			unless exists $valid_types{$type};
		$housing{$num}{$type} = $cost;
	}
	#
	# convert the bath increment to total cost
	#
	for my $n (keys %housing) {
		$housing{$n}{"single bath"} += $housing{$n}{"single"};
		$housing{$n}{"double bath"} += $housing{$n}{"double"};
	}
	close IN;
}

sub types {
	return sort {$valid_types{$a} <=> $valid_types{$b} } keys %valid_types;
}

sub cost {
	my ($pkg, $num, $type) = @_;
	return $housing{$num}{$type};
}

sub valid {
	my ($self, $type) = @_;
	return exists $valid_types{$type};
}

1;
