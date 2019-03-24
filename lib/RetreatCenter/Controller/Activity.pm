use strict;
use warnings;
package RetreatCenter::Controller::Activity;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    stash
    tt_today
    model
    time_travel_class
/;
use Date::Simple qw/
    date
    today
/;
use Time::Simple qw/
    get_time
/;

sub view : Local {
    my ($self, $c) = @_;

    # first we get a date defaulting to today
    my $cdate_obj;
    if (my $cdate_param = $c->req->query_parameters->{cdate}) {
        # $cdate_param could be in a variety of date formats
        $cdate_obj = date($cdate_param);
        if (! $cdate_obj) {
            $c->gen_error('Requested activity date is not valid.');
        }
    }
    else {
        $cdate_obj = tt_today($c);
    }
    # look for activity records on that date
    my @activities = model($c, 'Activity')->search(
                         {
                            cdate => $cdate_obj->as_d8(),
                         },
                         {
                            order_by => 'ctime asc',
                         }
                     );
    # there can be multiple activity records with the same time.
    # to keep things clean we want to display the time
    # only once per execution of the cronjob grab_new
    # which happens every 15 minutes 24/7.
    my @array;
    my $prev_time = '';
    my $time;
    for my $a (@activities) {
        my $t = $a->ctime();
        if ($prev_time eq $t) {
            $time = '';
        }
        else {
            $time = get_time($t)->t12();
            # 12 hour time is okay without the am/pm
            # it should be clear what's what.
            $prev_time = $t;
        }
        push @array, {
            message => $a->message(),
            time    => $time,
        };
    }
    $c->stash(
        time_travel_class($c),
        cdate    => $cdate_obj,
        prev     => ($cdate_obj-1)->as_d8(),
        next     => ($cdate_obj+1)->as_d8(),
        activity => \@array,
        template => "activity/view.tt2",
    );
}

1;
