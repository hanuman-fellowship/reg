#!/usr/local/bin/perl -w
package Util;
use strict;
use Exporter;

use vars '@ISA', '@EXPORT_OK';
@ISA = qw/Exporter/;
@EXPORT_OK = qw/slurp expand monthyear/;

#
# slurp an entire template into one variable
#
sub slurp {
    my ($fname) = @_;
	$fname = "templates/$fname.html" unless $fname =~ /\./;
    open IN, $fname
		or die "cannot open $fname: $!\n";
    local $/;
    my $s = <IN>;
    close IN;
    return $s;
}

#
# __, **, %%%, ~~ expansions into <i>, <b>, <a href=>, <a mailto>
#
# the first _ and * need to appear either after a blank
# or at the beginning of the line - in case an underscore
# is needed elsewhere - like in a web address.
#
sub expand {
	my ($v) = @_;
	$v =~ s#(^|\ )\*(.*?)\*#$1<b>$2</b>#smg;
	$v =~ s#(^|\ )_(.*?)\_#$1<i>$2</i>#smg;
	$v =~ s#%(.*?)%(.*?)%#<a href='http://$2' target=_blank>$1</a>#sg;
	$v =~ s{~(.*?)~}{<a href="mailto:$1">$1</a>}sg;
	my $in_list = "";
	my $out = "";
	for (split /\n/, $v) {
		unless (/\S/) {
			if ($in_list) {
				$out .= $in_list;
				$in_list = "";
			}
			$out .= "<p>\n";
			next;
		}
		if (s/^(#|-)/<li>/) {
			unless ($in_list) {
				if ($1 eq '#') {
					$out .= "<ol>\n";
					$in_list = "</ol>\n";
				} else {
					$out .= "<ul>\n";
					$in_list = "</ul>\n";
				}
			}
		}
		$out .= "$_\n";
	}
	$out .= $in_list if $in_list;
	$out;
}

sub monthyear {
    my ($sdate) = @_;
    return $sdate->format("%B %Y");
}

1;
