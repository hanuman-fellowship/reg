use strict;
use warnings;

package Util;
use base 'Exporter';
our @EXPORT_OK = qw/affil_table date_fmt slash_to_d8/;

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

sub date_fmt {
    my ($date_str) = @_;

    ($date_str =~ /\d{8}/)? d8($date_str)->format("%m/%d/%Y")
    :                       "";
}

sub slash_to_d8 {
    my ($date_str) = @_;
    
    if (my ($m, $d, $y) = $date_str =~ m{(\d\d)/(\d\d)/(\d+)}) {
        if ($y < 100) {
            $y = (($y > 70)? "19"
                 :           "20") . $y;
        }
        return "$y$m$d";
    }
    else {
        return "";
    }
}

1;
