use strict;
use warnings;
package RetreatCenter::Controller::Ride;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    empty
    model
    trim
    email_letter
/;
use Date::Simple qw/
    date
    today
    days_in_month
/;
use Time::Simple qw/
    get_time
/;
use Algorithm::LUHN qw/
    is_valid
/;
use Global qw/
    %string
/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

#
# show future rides
# and ones that have not yet been paid for.
#
sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{rides} = [ model($c, 'Ride')->search(
        -or => [
            pickup_date => { '>=' => today()->as_d8() },
            paid_date   => '',
        ],
        { order_by => 'pickup_date, airport, flight_time' }
    ) ];
    $c->stash->{template} = "ride/list.tt2";
}

# ???referential integrity - watch out!
# deletion of ride will be quite rare. but still...
# both registrations, rentals and config records
# reference ride.
sub delete : Local {
    my ($self, $c, $id) = @_;

    model($c, 'Ride')->find($id)->delete();
    Global->init($c, 1);
    $c->response->redirect($c->uri_for('/ride/list'));
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    @mess = ();
    if (! empty($hash{pickup_date})) {
        my $dt = date($hash{pickup_date});
        if ($dt) {
            $hash{pickup_date} = $dt->as_d8();
        }
        else {
            push @mess, "Invalid pick up date: $hash{pickup_date}";
        }
    }
    if (empty($hash{flight_time})) {
        push @mess, "Missing flight time.";
    }
    else {
        my $t = get_time($hash{flight_time});
        if (! $t) {
            push @mess, Time::Simple->error();
        }
        else {
            $hash{flight_time} = $t->t24();
        }
    }
    if (   $hash{cc_number1} !~ m{\d{4}}
        || $hash{cc_number2} !~ m{\d{4}}
        || $hash{cc_number3} !~ m{\d{4}}
        || $hash{cc_number4} !~ m{\d{4}}
    ) {
        push @mess, "Invalid credit card number";
    }
    if ($hash{cc_expire} !~ m{(\d\d)(\d\d)}) {
        push @mess, "Invalid expiration date";
    }
    my $month = $1;
    my $year = $2;
    if (! (1 <= $month && $month <= 12)) {
        push @mess, "Invalid month in expiration date";
    }
    else {
        my $today = today();
        my $cur_century = (int($today->year() / 100)) * 100;
            # another way to just get the century?

        my $exp_date = date($year + $cur_century,
                            $month,
                            days_in_month($year, $month)
                       );
        if ($today > $exp_date) {
            push @mess, "Credit card has expired";
        }
    }
    if ($hash{cc_code} !~ m{\d{3}}) {
        push @mess, "Invalid security code";
    }
    $hash{cc_number} = $hash{cc_number1} 
                     . $hash{cc_number2}
                     . $hash{cc_number3}
                     . $hash{cc_number4}
                     ;
    if (! is_valid($hash{cc_number})) {
        push @mess, "Credit card number is not valid.";
    }
    delete $hash{"cc_number$_"} for 1 .. 4;
    if (empty($hash{paid_date})) {
        $hash{paid_date} = '';      # to be sure???
    }
    else {
        my $dt = date($hash{paid_date});
        if ($dt) {
            $hash{paid_date} = $dt->as_d8();
        }
        else {
            push @mess, "Invalid paid date: $hash{paid_date}";
        }
    }
    # ...
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "ride/error.tt2";
    }
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $ride = $c->stash->{ride} = model($c, 'Ride')->find($id);
    $c->stash->{person} = $ride->rider();

    my (@roles) = model($c, "Role")->search({
        role => 'driver',
    });
    # should just be one role

    my @drivers = $roles[0]->users();
    my $driver_opts = "";
    for my $d (@drivers) {
        my $id = $d->id();
        $driver_opts .= "<option value=$id"
                     . (($ride->driver_id() == $id)? " selected": "")
                     . "> "
                     . $d->first() . " " . $d->last()
                     . "\n"
                     ;
    }
    $c->stash->{driver_opts} = $driver_opts;

    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "ride/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;
    my $ride = model($c, 'Ride')->find($id);
    my $rider = $ride->rider();
    $rider->update({
        cc_number => $hash{cc_number},
        cc_expire => $hash{cc_expire},
        cc_code   => $hash{cc_code},
    });
    delete @hash{qw/cc_number cc_expire cc_code/};
    $ride->update(\%hash);
    Global->init($c, 1);
    $c->response->redirect($c->uri_for('/ride/list'));
}

sub create : Local {
    my ($self, $c, $person_id) = @_;

    my (@roles) = model($c, "Role")->search({
        role => 'driver',
    });
    # should just be one role

    my @drivers = $roles[0]->users();
    my $driver_opts = "";
    for my $d (@drivers) {
        $driver_opts .= "<option value="
                     . $d->id()
                     . "> "
                     . $d->first() . " " . $d->last()
                     . "\n"
                     ;
    }
    $c->stash->{driver_opts} = $driver_opts;
    $c->stash->{person} = model($c, 'Person')->find($person_id);
    $c->stash->{form_action} = "create_do/$person_id";
    $c->stash->{template}    = "ride/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c, $person_id) = @_;

    _get_data($c);
    return if @mess;
    $hash{rider_id} = $person_id;
    my $p = model($c, 'Person')->find($person_id);
    $p->update({
        cc_number => $hash{cc_number},
        cc_expire => $hash{cc_expire},
        cc_code   => $hash{cc_code},
    });
    delete $hash{cc_number};
    delete $hash{cc_expire};
    delete $hash{cc_code};
    $hash{paid_date} = '';
    my $ride = model($c, 'Ride')->create(\%hash);
    $c->response->redirect($c->uri_for("/ride/view/" . $ride->id()));
}

# send email to driver and rider with the appropriate details.
#
sub send : Local {
    my ($self, $c, $id) = @_;

    my $ride = model($c, 'Ride')->find($id);
    my $driver = $ride->driver();
    my $rider = $ride->rider();
    # ??? check that there ARE email addresses...
    my $html = "hi <i>there</i>";
    email_letter($c,
        to      => $rider->email(),
        cc      => $driver->email(),
        from    => "$string{from_title} <$string{from}>",
        subject => "Ride Scheduled",
        html    => $html, 
    );
    $ride->update({
        sent_date => today()->as_d8(),
    });
    $c->response->redirect($c->uri_for("/ride/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{ride} = model($c, 'Ride')->find($id);
    $c->stash->{string} = \%string;
    $c->stash->{template} = "ride/view.tt2";
}

sub pay : Local {
    my ($self, $c) = @_;
    my @rides = model($c, 'Ride')->search({
        pickup_date => { '<=', today()->as_d8() },
        paid_date   => '',
    });
    $c->stash->{rides} = \@rides;
    $c->stash->{template} = "ride/pay.tt2";
}

sub pay_do : Local {
    my ($self, $c) = @_;

    my @paid_ids;
    for my $p ($c->request->param()) {
        if ($p =~ m{r(\d+)}) {
            push @paid_ids, $1;
        }
    }
    if (@paid_ids) {
        my $today = today()->as_d8();
        model($c, 'Ride')->search({
            id => { -in => \@paid_ids },
        })->update({
            paid_date => $today,          
        });
    }
    $c->forward('list');
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
        push @cond, pickup_date => { '>=' => $start->as_d8() };
    }
    my $end = $c->request->param('end');
    $end = date($end);
    if ($end) {
        push @cond, pickup_date => { '<=' => $end->as_d8() };
    }
    my $name = $c->request->param('name');
    $name =~ s{\*}{%}g;
    if (! empty($name)) {
        push @cond, 'rider.last' => { 'like' => "%$name%" };
    }
    if (! @cond) {
        # same as list
        #
        push @cond, -or => [
                        pickup_date => { '>=' => today()->as_d8() },
                        paid_date   => '',
                    ];
    }
    $c->stash->{rides} = [ model($c, 'Ride')->search(
        {
            @cond,
        },
        {
            order_by => 'pickup_date, airport, flight_time',
            join     => [qw/ rider /],
            prefetch => [qw/ rider /],   
        }
    ) ];
    $c->stash->{template} = "ride/list.tt2";
}

1;
