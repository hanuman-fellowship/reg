use strict;
use warnings;
package RetreatCenter::Controller::Ride;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    empty
    model
    trim
/;
use Date::Simple qw/
    date
    today
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
    $hash{cc_number} = $hash{cc_number1} 
                     . $hash{cc_number2}
                     . $hash{cc_number3}
                     . $hash{cc_number4}
                     ;
    delete $hash{"cc_number$_"} for 1 .. 4;
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

1;
