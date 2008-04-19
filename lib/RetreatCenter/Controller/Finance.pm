use strict;
use warnings;
package RetreatCenter::Controller::Finance;
use base 'Catalyst::Controller';

use Util qw/
    model
/;
use Date::Simple qw/date/;

sub index : Local {
    my ($self, $c) = @_;

    $c->stash->{template} = "finance/index.tt2";
}

sub new_deposit : Local {
    my ($self, $c) = @_;

    # replace by actual last deposit date/time
    my $last_date = "20080401";
    my $last_time = "00:00";

    my $cond = {
        -or => [
            the_date => { '>', $last_date },
            -and => [
                the_date => $last_date,
                time     => { '>=', $last_time },
            ],
        ],
    };
    my $order = {
        order_by => 'the_date, time',
    };
    my @reg_payments;
    my ($cash, $check, $credit, $online, $total) = (0) x 5;
    for my $p (model($c, 'RegPayment')->search($cond, $order)) {
        my $reg = $p->registration;
        my $per = $reg->person;
        my $type = $p->type;
        my $amt  = $p->amount;
        if ($type eq 'Cash') {
            $cash += $amt;
        }
        elsif ($type eq 'Check') {
            $check += $amt;
        }
        elsif ($type eq 'Credit Card') {
            $credit += $amt;
        }
        elsif ($type eq 'Online') {
            $online += $amt;
        }
        $total += $amt;
        push @reg_payments, {
            name   => $per->last . ", " . $per->first,
            reg_id => $reg->id,
            date   => $p->the_date_obj,
            cash   => ($type eq 'Cash'  )? $amt: "",
            chk    => ($type eq 'Check' )? $amt: "",
            credit => ($type eq 'Credit Card')? $amt: "",
            online => ($type eq 'Online')? $amt: "",
            pname  => $reg->program->name,
        };
    }
    # ??? COULD make links in the .tt2 file
    # to be able click over to the registration or the program
    # in a separate window (_blank)
    @reg_payments = sort {
                        $a->{name} cmp $b->{name}
                    }
                    @reg_payments;
    $c->stash->{reg_payments} = \@reg_payments;
    $c->stash->{cash} = $cash;
    $c->stash->{check} = $check;
    $c->stash->{credit} = $credit;
    $c->stash->{online} = $online;
    $c->stash->{total} = $total;
    $c->stash->{template} = "finance/deposit.tt2";
}

sub new_deposit_do : Local {
    my ($self, $c) = @_;
}

1;
