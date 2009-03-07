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
#
sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{rides} = [ model($c, 'Ride')->search(
        { pickup_date => { '>=' => today()->as_d8() } },
        { order_by => 'pickup_date' }
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
    if (! empty($hash{pickup_date})) {
        my $dt = date($hash{pickup_date});
        if ($dt) {
            $hash{pickup_date} = $dt->as_d8();
        }
        else {
            push @mess, "Invalid pick up date: $hash{pickup_date}";
        }
    }
    @mess = ();
    # ...
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "ride/error.tt2";
    }
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $ride = $c->stash->{ride} = model($c, 'Ride')->find($id);
    my $type = $ride->type();
    my $opts = "";
    for my $t (qw/ U D C S O /) {
        $opts .= "<option value='$t'";
        if ($t eq $type) {
            $opts .= " selected";
        }
        $opts .= ">" . $string{'payment_' . $t} . "\n";
    }
    $c->stash->{type_opts} = $opts;

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
    model($c, 'Ride')->find($id)->update(\%hash);
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
    $c->stash->{type_opts} = <<"EOT";
<option value=U selected>Due
<option value=D>Credit Card
<option value=C>Check
<option value=S>Cash
<option value=O>Online
EOT
    $c->stash->{form_action} = "create_do/$person_id";
    $c->stash->{template}    = "ride/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c, $person_id) = @_;

    _get_data($c);
    return if @mess;
    $hash{rider_id} = $person_id;
    my $ride = model($c, 'Ride')->create(\%hash);
    $c->response->redirect($c->uri_for("/ride/view/" . $ride->id()));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{ride} = model($c, 'Ride')->find($id);
    $c->stash->{string} = \%string;
    $c->stash->{template} = "ride/view.tt2";
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
