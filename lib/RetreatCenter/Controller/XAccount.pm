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
    invalid_amount
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

    stash($c,
        mmc_checked => 'checked',
        mmi_checked => '',
        form_action => "create_do",
        template    => "xaccount/create_edit.tt2",
    );
}

my %P;
my @mess;
sub _get_data {
    my ($c) = @_;

    %P = %{ $c->request->params() };
    @mess = ();
    if (empty($P{descr})) {
        push @mess, "Description cannot be blank";
    }
    if (empty($P{glnum})) {
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

    my $xa = model($c, 'XAccount')->create(\%P);
    my $id = $xa->id();
    $c->response->redirect($c->uri_for("/xaccount/list"));
}

sub view : Local {
    my ($self, $c, $id, $by_person) = @_;

    my $xa = model($c, 'XAccount')->find($id);
    my @payments = model($c, 'XAccountPayment')->search(
        {
            xaccount_id => $id,
        },
        {
            join     => 'person',
            prefetch => 'person',
            order_by => $by_person? [qw/ person.last person.first me.id /]
                        :           'the_date desc',
        }
    );
    stash($c,
        by_person => $by_person,
        payments  => \@payments,
        xaccount  => $xa,
        template  => "xaccount/view.tt2",
    );
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

    my $xa = model($c, 'XAccount')->find($id);
    my $sponsor = $xa->sponsor();
    stash($c,
        mmc_checked => $sponsor eq 'mmc'? 'checked': '',
        mmi_checked => $sponsor eq 'mmi'? 'checked': '',
        xaccount    => model($c, 'XAccount')->find($id),
        form_action => "update_do/$id",
        template    => "xaccount/create_edit.tt2",
    );
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    model($c, 'XAccount')->find($id)->update(\%P);
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
    my @accts = model($c, 'XAccount')->search(
                    undef,
                    { order_by => 'descr' },
                );
    my $cr_misc_id = 0;
    ACCT:
    for my $a (@accts) {
        if ($a->descr() eq 'Credit Card Misc') {
            $cr_misc_id = $a->id();
            last ACCT;
        }
    }
    stash($c,
        message   => payment_warning('mmc'),
        person    => model($c, 'Person')->find($person_id),
        xaccounts => \@accts,
        credit_misc_id => $cr_misc_id,
        template       => "xaccount/pay_balance.tt2",
    );
}

sub pay_balance_do : Local {
    my ($self, $c) = @_;

    my $amt = $c->request->params->{amount} || "";
    if (invalid_amount($amt)) {
        error($c,
            "Illegal Amount: $amt",
            "xaccount/error.tt2",
        );
        return;
    }
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

sub del_payment : Local {
    my ($self, $c, $payment_id) = @_;

    my $pay = model($c, 'XAccountPayment')->find($payment_id);
    my $person_id = $pay->person_id();
    $pay->delete();
    $c->response->redirect($c->uri_for("/person/view/$person_id"));
}

sub update_payment : Local {
    my ($self, $c, $payment_id) = @_;

    my $payment = model($c, 'XAccountPayment')->find($payment_id);
    my $type_opts = "";
    for my $t (qw/ D C S O /) {
        $type_opts .= "<option value=$t"
                   .  (($payment->type() eq $t)? " selected": "")
                   .  ">"
                   .  $string{"payment_$t"}
                   .  "\n";
                   ;
    }
    stash($c,
        payment   => $payment,
        type_opts => $type_opts,
        person    => $payment->person(),
        xaccounts => [ model($c, 'XAccount')->search(
            undef,
            { order_by => 'descr' }
        ) ],
        template  => "xaccount/update_payment.tt2",
    );
}

sub update_payment_do : Local {
    my ($self, $c, $payment_id) = @_;

    my $payment = model($c, 'XAccountPayment')->find($payment_id);
    my $the_date = trim($c->request->params->{the_date});
    my $dt = date($the_date);
    if (!$dt) {
        error($c,
            "Illegal Date: $the_date",
            "xaccount/error.tt2",
        );
        return;
    }
    my $amount = trim($c->request->params->{amount});
    if (invalid_amount($amount)) {
        error($c,
            "Illegal Amount: $amount",
            "xaccount/error.tt2",
        );
        return;
    }
    my $type = $c->request->params->{type};
    $payment->update({
        the_date    => $dt->as_d8(),
        amount      => $amount,
        type        => $type,
        what        => $c->request->params->{what},
        xaccount_id => $c->request->params->{xaccount_id},
    });
    # ??? does not update the time.  okay?

    my $person_id = $payment->person_id();
    $c->response->redirect($c->uri_for("/person/view/$person_id"));
}

1;
