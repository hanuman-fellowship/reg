use strict;
package Canpol;

my %canpol;

sub init {
	open IN, "canpol.tmp"
		or die "cannot open canpol.tmp: $!\n";
	my $code;
    while (<IN>) {
        s/\cM\n//;
        my ($k, $v) = split /\t/;
        $v =~ s/^\s*|\s*$//g;
        if ($v eq "-") {
            $v = "";
            while (<IN>) {
                s/\cM\n//;
                last if $_ eq ".";
                $v .= "$_\n";
            }
        }
		if ($k eq "code") {
			$code = $v;
		}
		else {
			chomp $v;
			$canpol{$code} = $v;
		}
	}
	close IN;
}

sub policy {
	my ($class, $code) = @_;
	if (exists $canpol{$code}) {
		return $canpol{$code};
	}
	else {
		return "Unknown cancellation policy";
	}
}

init;

1;
