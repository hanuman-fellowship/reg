use strict;
use warnings;
package RetreatCenter::Controller::Summary;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    model
/;

sub view : Local {
    my ($self, $c, $id) = @_;

    my $summary = model($c, 'Summary')->find($id);
    if (my ($program) = $summary->program()) {
        $c->stash->{type} = 'program';
        $c->stash->{Type} = 'Program';
        $c->stash->{happening} = $program;
    }
    elsif (my ($rental) = $summary->rental()) {
        $c->stash->{type} = 'rental';
        $c->stash->{Type} = 'Rental';
        $c->stash->{happening} = $rental;
    }
    else {
        $c->stash->{mess}     = "Unknown source for summary";
        $c->stash->{template} = "gen_error.tt2";
    }
    $c->stash->{sum} = $summary;
    $c->stash->{template} = "summary/view.tt2";
}

sub update : Local {
    my ($self, $c, $type, $id) = @_;
 
    my $happening = model($c, $type)->find($id);
    $c->stash->{Type}      = $type;
    $c->stash->{type}      = lc $type;
    $c->stash->{happening} = $happening;
    $c->stash->{sum}       = $happening->summary;
    $c->stash->{template}  = "summary/edit.tt2";
}
sub update_do : Local {
    my ($self, $c, $id) = @_;
    my $sum = model($c, 'Summary')->find($id);
}

1;
