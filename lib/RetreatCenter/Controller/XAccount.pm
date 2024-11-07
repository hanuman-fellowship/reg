use strict;
use warnings;
package RetreatCenter::Controller::XAccount;
use base 'Catalyst::Controller';

use lib '../..';
use Date::Simple qw/
    date
    today
    ymd
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
    read_only
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

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
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
    if ($P{glnum} !~ m{ \A [0-9A-Z]* \z }xms) {
        push @mess, "GL Number must be digits and A-Z only";
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

    # We could add a relationship to the XAccount model
    # that does the code below for us.
    # This is a task for a future refactorer.
    # Or perhaps we need this code to enable the by_person feature?
    #
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

    my ($role) = model($c, 'Role')->search({
                     role => 'account_admin',
                 });
    my @users = $role->users;
    stash($c,
        acct_admin => @users? $users[0]->first: 'No Account Admin :(!',
        xaccounts  => [ model($c, 'XAccount')->search(
                            undef,
                            { order_by => 'sponsor, descr' },
                        )
                      ],
        template   => "xaccount/list.tt2",
    );
}

sub export : Local {
    my ($self, $c) = @_;

    my $csv;
    if (!open $csv, '>', '/var/Reg/report/xaccounts.csv') {
        error($c,
              'Cannot open xaccounts.csv',
              'gen_error.tt2',
        );
        return;
    }
    for my $xa (model($c, 'XAccount')->search(
                    undef,
                    { order_by => 'sponsor, descr' },
                )
    ) {
        print {$csv} join(', ', uc $xa->sponsor, '"'.$xa->descr.'"', $xa->glnum), "\n";
    }
    close $csv;
    $c->response->redirect($c->uri_for('/report/show_report_file/xaccounts.csv'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
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
# can't delete xaccount if any payments are present.
#
sub delete : Local {
    my ($self, $c, $id) = @_;

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    my @payments = model($c, 'XAccountPayment')->search({
        xaccount_id => $id,
    });
    if (@payments) {
        error($c,
              'You must first remove all payments.',
              'gen_error.tt2',
        );
        return;
    }
    model($c, 'XAccount')->find($id)->delete();
    $c->response->redirect($c->uri_for('/xaccount/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

sub prep_pay_balance : Local {
    my ($self, $c, $person_id) = @_;

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    stash($c,
        person    => model($c, 'Person')->find($person_id),
        template  => 'xaccount/prep_pay_balance.tt2',
    );
}

sub pay_balance : Local {
    my ($self, $c, $person_id) = @_;

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    if (tt_today($c)->as_d8() eq $string{last_deposit_date}) {
        error($c,
              'Since a deposit was just done'
                  . ' please make this payment tomorrow instead.',
              'gen_error.tt2');
        return;
    }
    my $sponsor   = $c->request->params->{sponsor}   || "mmc";
    my $timeframe = $c->request->params->{timeframe} || "current";
    my $st_label  = uc($sponsor) . " " . ucfirst $timeframe;

    my @spons_accts = model($c, 'XAccount')->search(
                    { sponsor => $sponsor },
                    { order_by => 'descr' },
                );
    # now to eliminate the accounts outside the timeframe
    my @accts;
    my $today = today();
    my $now = ymd($today->year(), $today->month, 1);
    my $year_ago = ymd($today->year() - 1, $today->month, 1);
    ACCT:
    for my $a (@spons_accts) {
        if ($a->descr() =~ /Membership/) {
            # must go through Members link
            next ACCT;
        }
        my ($m, $y) = $a->descr() =~ m{(\d+)/(\d+)}xms;
        my $acct_date = $y? ymd(2000 + $y, $m, 1): $now;
        my $acct_is_past = $acct_date < $year_ago;
        if ($acct_is_past && $timeframe eq 'past'
            ||
            !$acct_is_past && $timeframe eq 'current'
        ) {
            push @accts, $a;
        }
    }
    my $cr_nonprog_id = 0;
    ACCT:
    for my $a (@accts) {
        if ($a->descr() eq $string{credit_nonprog}) {
            $cr_nonprog_id = $a->id();
            last ACCT;
        }
    }
    stash($c,
        message   => payment_warning('mmc'),
        st_label  => $st_label,
        person    => model($c, 'Person')->find($person_id),
        xaccounts => \@accts,
        credit_nonprog_id => $cr_nonprog_id,
        credit_nonprog_people => $string{credit_nonprog_people},
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

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    my $pay = model($c, 'XAccountPayment')->find($payment_id);
    stash($c,
        payment  => $pay,
        template => 'xaccount/del_payment.tt2',
    );
}

sub del_payment_do : Local {
    my ($self, $c, $payment_id) = @_;

    my $pay = model($c, 'XAccountPayment')->find($payment_id);

    my $what = $pay->what();
    if ($what =~ m{mr_ids}xms) {
        # a meal request payment.
        # first we delete the meal_requests records
        my ($mr_ids) = $pay->what() =~ m{mr_ids(.*)}xms;
        my @mr_ids = $mr_ids =~ m{(\d+)}xmsg;
        for my $mr_id (@mr_ids) {
            my $mr = model($c, 'MealRequests')->find($mr_id);
            $mr->delete();
        }
        # could have done a single delete: where id in ()
        # but how within DBIC?
    }

    # the payment
    $pay->delete();

    my $person_id = $pay->person_id();
    $c->response->redirect($c->uri_for("/person/view/$person_id"));
}

sub update_payment : Local {
    my ($self, $c, $payment_id) = @_;

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
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
