use strict;
use warnings;
package RetreatCenter::Controller::Donation;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    trim
    model
    tt_today
    payment_warning
/;
use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->response->redirect($c->uri_for('/person/search'));
}

sub create : Local {
    my ($self, $c, $person_id) = @_;

    $c->stash->{person} = model($c, 'Person')->find($person_id);
    $c->stash->{projects} = [
        model($c, 'Project')->search(
            undef,
            { order_by => 'descr' },
        )
    ];
    $c->stash->{message}     = payment_warning('mmc');
    $c->stash->{form_action} = "create_do/$person_id";
    $c->stash->{template}    = "donation/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c, $person_id) = @_;

    my $amount = trim($c->request->params->{amount});
    my $project_id = $c->request->params->{project};
    my $dt = $c->request->params->{the_date};
    my $type = $c->request->params->{type};
    my $the_date = date($dt);
    my @mess = ();
    if ($amount !~ m{^\d+$}) {
        push @mess, "Illegal amount: $amount";
    }
    if (! ref($the_date)) {
        push @mess, "Illegal date: $dt";
    }
    if (@mess) {
        $c->stash->{mess}  = join "<br>\n", @mess;
        $c->stash->{template} = "donation/error.tt2";
        return; 
    }
    # check and report errors???
 
    model($c, 'Donation')->create({
        amount     => $amount,
        type       => $type,
        project_id => $project_id,
        person_id  => $person_id,
        the_date   => $the_date->as_d8(),
        who_d       => $c->user->obj->id,
        date_d      => tt_today($c)->as_d8(),
        time_d      => get_time()->t24(),
    });
    $c->response->redirect($c->uri_for("/person/view/$person_id"));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
