use strict;
use warnings;

package Util;
use base 'Exporter';
our @EXPORT_OK = qw/
    affil_table
    role_table
    leader_table
    trim
    nsquish
    slurp
    expand
    monthyear
    resize
    housing_types
    parse_zips
/;

use POSIX   qw/ceil/;
use Date::Simple qw/d8/;
use Lookup;

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
sub role_table {
    my ($c) = shift;

    my %checked = map { $_->id() => 'checked' } @_;

    join "\n",
    map {
        my $id = $_->id();
          "<tr><td>"
        . "<input type=checkbox name=role$id  $checked{$id}> "
        . $_->fullname
        . "</td></tr>"
    }
    sort {
        $a->fullname cmp $b->fullname
    }
    $c->model('RetreatCenterDB::Role')->all();
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
        "<input type=checkbox name=lead$id  $checked{$id}> $last, $first";
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

    if (index($fname, '.') == -1) {
        $fname .= ".html";
    }
    open my $in, "<", "root/static/templates/$fname"
		or die "cannot open r/s/t/$fname: $!\n";
    local $/;
    my $s = <$in>;
    close $in;
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
    $v =~ s{\r?\n}{\n}g;
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

#
# invoke ImageMagick convert to create
# the thumbnail and large images from the original
#
# if you only want to resize one of the two
# give the optional third parameter.
#
sub resize {
    my ($type, $id, $which) = @_;

    chdir "root/static/images";
    if (!$which || $which eq "imgwidth") {
        system("convert -scale $lookup{imgwidth}x"
              ." ${type}o-$id.jpg ${type}th-$id.jpg");
    }
    if (!$which || $which eq "big_imgwidth") {
        system("convert -scale $lookup{big_imgwidth}x"
              ." ${type}o-$id.jpg ${type}b-$id.jpg");
    }
    chdir "../../..";       # must cd back!   not stateless HTTP, exactly
}

sub housing_types {
    return qw/
		unknown
		commuting
		own_tent
		own_van
		center_tent
		economy
		dormitory
		quad
		triple
		double
		double_bath
		single
		single_bath
    /;
}

#
# returns either an array_ref of array_ref of zip code ranges
# or a scalar which is an error message.
#
sub parse_zips {
    my ($s) = @_;
    $s =~ s/\s*,\s*/,/g;

    # Check for zip range validity
    if ($s =~ m/[^0-9,-]/) {
        return "Only digits, commas, spaces and hyphen allowed"
              ." in the zip range field.";
    }

    my @ranges = split /,/, $s, -1;

    my $ranges_ref = [];
    for my $r (@ranges) {
        # Field must be either a zip range or a single zip
        if ($r =~ m/^(\d{5})-(\d{5})$/) {
            my ($startzip, $endzip) = ($1, $2);

            if ($startzip > $endzip) {
                return "Zip range start is greater than end";
            }
            push @$ranges_ref, [ $startzip, $endzip ];
        } 
        elsif ($r =~ m/^\d{5}$/) {
            push @$ranges_ref, [ $r, $r ];
        }
        else {
            return "Please provide a valid 5 digit zip code (xxxxx)"
                  ." or zip range (xxxxx-yyyyy)";
        }
    }
    return $ranges_ref;
}

1;
