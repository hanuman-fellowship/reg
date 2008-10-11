use strict;
use warnings;
package RetreatCenter::Controller::Summary;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    model
    lines
    etrim
    tt_today
/;
my @bools = qw/
    school_spaces
    vacate_early
    need_books
    participant_list
    schedule
    yoga_classes
    work_study
/;

sub view : Local {
    my ($self, $c, $type, $id) = @_;

    my $summary = model($c, 'Summary')->find($id);
    $c->stash->{type} = $type;
    $c->stash->{Type} = ucfirst $type;
    $c->stash->{happening} = $summary->$type();
    $c->stash->{sum} = $summary;
    $c->stash->{template} = "summary/view.tt2";
}

sub update : Local {
    my ($self, $c, $type, $id) = @_;
 
    my $happening = model($c, $type)->find($id);
    $c->stash->{Type}      = $type;
    $c->stash->{type}      = lc $type;
    $c->stash->{happening} = $happening;
    my $sum = $happening->summary;
    $c->stash->{sum}       = $sum;
    for my $f (qw/
        signage
        miscellaneous
        feedback
        food_service
        flowers
        lodging
        special_needs
        finances
        field_staff_setup
        sound_setup
    /) {
        $c->stash->{"$f\_rows"} = lines($sum->$f()) + 3;    # 3 in strings?
    }
    for my $f (@bools) {
        $c->stash->{"checked\_$f"} = $sum->$f()? "checked": "";
    }
    $c->stash->{template} = "summary/edit.tt2";
}
sub update_do : Local {
    my ($self, $c, $type, $id) = @_;
    my $sum = model($c, 'Summary')->find($id);
    my %hash = %{ $c->request->params() };
    for my $f (keys %hash) {
        $hash{$f} = etrim($hash{$f});
    }
    for my $f (@bools) {
        # since unchecked boxes are not sent...
        $hash{$f} = "" unless exists $hash{$f};
    }
    # delete ones that have not changed???
    # warn about ones that are different? we don't know what it was before
    # do we?  nope.
    $sum->update({
        %hash,
        date_updated => tt_today($c)->as_d8(),
        who_updated  => $c->user->obj->id,
        time_updated => sprintf "%02d:%02d", (localtime())[2, 1],
    });
    $c->response->redirect($c->uri_for("/summary/view/$type/$id"));
}

1;
