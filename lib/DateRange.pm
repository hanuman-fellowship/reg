use strict;
use warnings;
package DateRange;

use base 'Exporter';
our @EXPORT = qw/overlap/;

sub new {
    my ($class, $sdate, $edate) = @_;
    bless {
        sdate => $sdate,
        edate => $edate,
    }, $class;
}

# either an instance method 
# or an exported sub.
sub overlap {
    my ($dr1, $dr2) = @_;

    my $s1 = $dr1->sdate;
    my $e1 = $dr1->edate;
    my $s2 = $dr2->sdate;
    my $e2 = $dr2->edate;
    my $max_sdate = ($s1 > $s2)? $s1: $s2;
    my $min_edate = ($e1 > $e2)? $e2: $e1;
    if ($max_sdate <= $min_edate) {
        bless {
            sdate => $max_sdate,
            edate => $min_edate,
        }, 'DateRange';
    }
    else {
        return undef;
    }
}

sub sdate {
    my ($self) = @_;
    $self->{sdate};
}
sub edate {
    my ($self) = @_;
    $self->{edate};
}

sub show {
    my ($self) = @_;
    $self->sdate . " - " . $self->edate;
}

1;
