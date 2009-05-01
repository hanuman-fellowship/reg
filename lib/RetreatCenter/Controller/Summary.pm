use strict;
use warnings;
package RetreatCenter::Controller::Summary;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;
use Util qw/
    model
    lines
    etrim
    tt_today
    highlight
    stash
/;

sub view : Local {
    my ($self, $c, $type, $id) = @_;

    my $summary = model($c, 'Summary')->find($id);
    for my $f (qw/
        gate_code
        alongside
        registration_location
        orientation
        wind_up
        alongside
        back_to_back
        leader_name
        leader_housing
        staff_arrival
        staff_departure
        converted_spaces
    /) {
        $c->stash->{$f} = highlight($summary->$f());
    }

    my $happening = $summary->$type();
    my $sdate = $happening->sdate();
    my $nmonths = date($happening->edate())->month()
                - date($sdate)->month()
                + 1;
    my @opt = ();
    if ($type eq 'program') {
        my $extra = $happening->extradays();
        if ($extra) {
            my $edate2 = $happening->edate_obj() + $extra;
            stash($c,
                plus => "<b>Plus</b> $extra day"
                      . ($extra > 1? "s": "")
                      . " <b>To</b> " . $edate2
                      . " <span class=dow>"
                      . $edate2->format("%a")
                      . "</span>"
            );
        }
    }

    stash($c,
        type      => $type,
        Type      => ucfirst $type,
        happening => $happening,
        @opt,
        sum       => $summary,
        cal_param => "$sdate/$nmonths",
        template  => "summary/view.tt2",
    );
}

sub update : Local {
    my ($self, $c, $type, $id, $anchor) = @_;
 
    my $happening = model($c, $type)->find($id);
    $c->stash->{Type}      = $type;
    $c->stash->{type}      = lc $type;
    $c->stash->{happening} = $happening;
    my $sum = $happening->summary;
    $c->stash->{sum}       = $sum;
    for my $f (qw/
        leader_housing
        signage
        miscellaneous
        feedback
        food_service
        flowers
        field_staff_setup
        sound_setup
        check_list
        converted_spaces
    /) {
        $c->stash->{"$f\_rows"} = lines($sum->$f()) + 5;    # 5 in strings?
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

sub use_template : Local {
    my ($self, $c, $type, $happening_id, $sum_id) = @_;

    # $type is Program or Rental
    # $happening_id is the id of the Program or Rental

    # use the summary from the right template
    #
    my $prefix = "MMC";
    if ($type eq 'Program') {
        my $prog = model($c, $type)->find($happening_id);
        if ($prog->school() != 0) {
            $prefix = "MMI";
        }
    }
    my @prog = model($c, 'Program')->search({
        name => $prefix . " Template",
    });
    if (! @prog) {
        $c->stash->{mess} = "Could not find '$prefix Template' program";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }
    my $template_sum = model($c, 'Summary')->find($prog[0]->summary_id());
    model($c, 'Summary')->find($sum_id)->update({
        $template_sum->get_columns(),

        # and then override the following:
        id           => $sum_id,
        date_updated => tt_today($c)->as_d8(),
        who_updated  => $c->user->obj->id,
        time_updated => get_time()->t24(),
    });
    $type = lc $type;       # Program to program
    $c->response->redirect($c->uri_for("/summary/view/$type/$sum_id"));
}

1;
