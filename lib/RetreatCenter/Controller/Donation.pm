use strict;
use warnings;
package RetreatCenter::Controller::Donation;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    trim
    model
    tt_today
/;
use Date::Simple qw/
    date
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
    $c->stash->{form_action} = "create_do/$person_id";
    $c->stash->{template}    = "donation/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c, $person_id) = @_;

    my $amount = trim($c->request->params->{amount});
    my $project_id = $c->request->params->{project};
    my $dt = $c->request->params->{date_donate};
    my $date_donate = date($dt);
    my @mess = ();
    if ($amount !~ m{^\d+$}) {
        push @mess, "Illegal amount: $amount";
    }
    if (! ref($date_donate)) {
        push @mess, "Illegal date: $dt";
    }
    if (@mess) {
        $c->stash->{mess}  = join "<br>\n", @mess;
        $c->stash->{template} = "donation/error.tt2";
        return; 
    }
    # check and report errors???
 
    model($c, 'Donation')->create({
        amount      => $amount,
        project_id  => $project_id,
        person_id   => $person_id,
        date_donate => $date_donate->as_d8(),
        who_d       => $c->user->obj->id,
        date_d      => tt_today($c)->as_d8(),
        time_d      => sprintf "%02d:%02d", (localtime())[2, 1],
    });
    $c->response->redirect($c->uri_for("/person/view/$person_id"));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
