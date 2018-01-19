use strict;
use warnings;
package RetreatCenter::Controller::Meal;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    empty
    model
    trim
    error
    stash
    get_now
/;
use Date::Simple qw/
    date
    today
/;
use Time::Simple qw/
    get_time
/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

#
# show future meal
#
sub list : Local {
    my ($self, $c) = @_;

    stash($c,
        pg_title => "Meals",
        meals => [ model($c, 'Meal')->search(
            {
                edate => { '>=' => today()->as_d8() },
            },
            {
                order_by => 'sdate',
            }
        ) ],
        template => "meal/list.tt2",
    );
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $meal = model($c, 'Meal')->find($id);
    stash($c,
        pg_title => 'Meal',
        meal    => $meal,
        template => "meal/view.tt2",
        daily_pic_date => "indoors/" . $meal->sdate(),
        cluster_date   => $meal->sdate(),
    );
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    my $meal = model($c, 'Meal')->find($id);
    $meal->delete();
    $c->response->redirect($c->uri_for('/meal/list'));
}

my %P;
my @mess;
my $edate1;
sub _get_data {
    my ($c) = @_;

    %P = %{ $c->request->params() };
    for my $k (keys %P) {
        $P{$k} = trim($P{$k});
    }
    @mess = ();
    if (empty($P{sdate})) {
        push @mess, "Missing Start Date";
    }
    else {
        my $dt = date($P{sdate});
        if ($dt) {
            $P{sdate} = $dt->as_d8();
        }
        else {
            push @mess, "Invalid Start Date: $P{sdate}";
        }
    }
    if (empty($P{edate})) {
        push @mess, "Missing End Date";
    }
    else {
        Date::Simple->relative_date(date($P{sdate}));
        my $dt = date($P{edate});
        Date::Simple->relative_date();
        if ($dt) {
            $P{edate} = $dt->as_d8();
            $edate1 = ($dt-1)->as_d8();
        }
        else {
            push @mess, "Invalid End Date: $P{edate}";
        }
    }
    if (! @mess && $P{sdate} > $P{edate}) {
        push @mess, "Start date must be before the End date";
    }
    for my $m (qw/ breakfast lunch dinner /) {
        if (empty($P{$m})) {
            $P{$m} = 0;
        }
        elsif ($P{$m} !~ m{^-?\d+$}) {
            push @mess, "Invalid # for " . ucfirst($m) . ": $P{$m}";
        }
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "meal/error.tt2";
    }
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $meal = $c->stash->{meal} = model($c, 'Meal')->find($id);
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "meal/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    my $meal = model($c, 'Meal')->find($id);

    $meal->update(\%P);
    $c->response->redirect($c->uri_for("/meal/list/"));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "meal/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;
    model($c, 'Meal')->create({
        %P,
        get_now($c),
    });
    $c->response->redirect($c->uri_for("/meal/list/"));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

sub search : Local {
    my ($self, $c) = @_;
    
    my @cond = (); 
    my $start = $c->request->param('start');
    $start = date($start);
    if ($start) {
        push @cond, sdate => { '>=' => $start->as_d8() };
    }
    if (! @cond) {
        # same as list
        #
        $c->response->redirect($c->uri_for('/meal/list'));
        return;
    }
    stash($c,
        pg_title => "Meals",
        meals => [ model($c, 'Meal')->search(
            {
                @cond,
            },
            {
                order_by => 'sdate',
                rows     => 10,     # limit it on purpose
                                    # otherwise too many ...
            }
        ) ],
        template => "meal/list.tt2",
    );
}

1;
