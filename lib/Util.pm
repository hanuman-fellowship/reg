use strict;
use warnings;

package Util;
use base 'Exporter';
our @EXPORT_OK = qw/
    affil_table
    leader_table
    trim
    nsquish
    slurp
    expand
    monthyear
/;

use POSIX   qw/ceil/;
use Date::Simple qw/d8/;

my ($naffils, @affils, %checked);

sub _affil_elem {
    my ($i) = @_;
    if ($i >= $naffils) {
        return "<td>&nbsp;</td>";
    }
    my $a = $affils[$i];
    my $id = $a->id();
    my $descrip = $a->descrip();
    return "<td><input type=checkbox name=aff$id "
           . ($checked{$id} || "")
           . ">"
           . $descrip
           . "</td>";
}


#
# get the affiliations table ready for the template.
# this was too hard to do within the template...
# which affils should be checked?
#
# the first parameter is the Catalyst context.
# the next are Afill objects that you want checked.
#
sub affil_table {
    my ($c) = shift;
    %checked = map { $_->id() => 'checked' } @_;

    @affils = $c->model('RetreatCenterDB::Affil')->search(
        undef,
        { order_by => 'descrip' },
    );
    # figure the number of affils in the first and second column.
    $naffils = @affils;
    my $n = ceil($naffils/3);

    my ($aff);
    for my $i (0 .. $n-1) {
        $aff .= "<tr>";

        $aff .= _affil_elem($i);
        $aff .= _affil_elem($i+$n);
        $aff .= _affil_elem($i+2*$n);

        $aff .= "</tr>\n";
    }
    $aff;
}

#
sub leader_table {
    my ($c) = shift;

    my %checked = map { $_->id() => 'checked' } @_;

    join "<br>\n",
    map {
        my $id = $_->id();
        my $last = $_->person->last();
        my $first = $_->person->first();
        "<input type=checkbox name=lead$id  $checked{$id}>$last, $first";
    }
    sort {
        $a->person->last()   cmp $b->person->last() or
        $a->person->first () cmp $b->person->first()
    }
    $c->model('RetreatCenterDB::Leader')->all();
}

#
# trim leading and trailing blanks off the parameter
# and return the result
#
sub trim {
    my ($s) = @_;

    $s =~ s{^\s*|\s*$}{}g;
    $s;
}

#
# take the parameters, concatenate them,
# extract the digits in order and suffix
# them with the first letter.
#
# this is used during the efforts to locate
# a duplicate entry.   If an address is
# spelled differently or road instead of rd
# it will have the same nsquished value.
#
# this is a poor man's MD5.
# or an address-specific MD5.
#
sub nsquish {
    my $s = join '', @_;
    my ($c) = $s =~ m{([a-z])}i;
    $s =~ s{\D}{}g;
    $s.(uc $c);
}

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
