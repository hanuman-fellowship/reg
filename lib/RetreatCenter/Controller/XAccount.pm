use strict;
use warnings;
package RetreatCenter::Controller::XAccount;
use base 'Catalyst::Controller';

use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;
use Util qw/
    trim
    empty
    model
    tt_today
    stash
    payment_warning
    error
/;
use Global qw/
    %string
/;

use lib '../../';       # so you can do a perl -c here.

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "xaccount/create_edit.tt2";
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    @mess = ();
    if (empty($hash{descr})) {
        push @mess, "Description cannot be blank";
    }
    if (empty($hash{glnum})) {
        push @mess, "GL Number cannot be blank";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "xaccount/error.tt2";
    }
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;

    my $xa = model($c, 'XAccount')->create(\%hash);
    my $id = $xa->id();
    $c->response->redirect($c->uri_for("/xaccount/list"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $xa = model($c, 'XAccount')->find($id);
    $c->stash->{xaccount} = $xa;
    $c->stash->{template} = "xaccount/view.tt2";
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{xaccounts} = [
        model($c, 'XAccount')->search(
            undef,
            { order_by => 'descr' },
        )
    ];
    $c->stash->{template} = "xaccount/list.tt2";
}

sub update : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{xaccount}    = model($c, 'XAccount')->find($id);
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "xaccount/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    model($c, 'XAccount')->find($id)->update(\%hash);
    $c->response->redirect($c->uri_for("/xaccount/view/$id"));
}

#
# does this delete the payments???
# no.
#
sub delete : Local {
    my ($self, $c, $id) = @_;

    model($c, 'XAccount')->find($id)->delete();
    $c->response->redirect($c->uri_for('/xaccount/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

sub pay_balance : Local {
    my ($self, $c, $person_id) = @_;

    if (tt_today($c)->as_d8() eq $string{last_deposit_date}) {
        error($c,
              'Since a deposit was just done'
                  . ' please make this payment tomorrow instead.',
              'gen_error.tt2');
        return;
    }
    stash($c,
        message  => payment_warning($c),
        person => model($c, 'Person')->find($person_id),
        xaccounts => [
            model($c, 'XAccount')->search(
                undef,
                { order_by => 'descr' },
            )
        ],
        template => "xaccount/pay_balance.tt2",
    );
}

sub pay_balance_do : Local {
    my ($self, $c) = @_;

    my $amt = $c->request->params->{amount};
    my $xaccount_id = $c->request->params->{xaccount_id};
    my $person_id = $c->request->params->{person_id};
    my $what = $c->request->params->{what};
    my $type = $c->request->params->{type};
    my $now_date = tt_today($c)->as_d8();
    model($c, 'XAccountPayment')->create({
        xaccount_id => $xaccount_id,
        person_id   => $person_id,
        amount      => $amt,
        type        => $type,
        what        => $what,

        user_id     => $c->user->obj->id,
        the_date    => $now_date,
        time        => get_time()->t24(),
    });
    $c->response->redirect($c->uri_for("/person/view/$person_id"));
}

1;
