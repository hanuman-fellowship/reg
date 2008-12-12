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

    # ??? replace by actual last deposit date/time
    my $last_date = "20081101";
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
    my @payments;
    my ($cash, $check, $credit, $online, $total) = (0) x 5;
    for my $src (qw/ Reg XAccount Rental /) {
        for my $p (model($c, "${src}Payment")->search($cond)) {
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
            push @payments, {
                name   => $p->name,
                link   => $p->link,
                date   => $p->the_date_obj,
                cash   => ($type eq 'Cash'  )? $amt: "",
                chk    => ($type eq 'Check' )? $amt: "",
                credit => ($type eq 'Credit Card')? $amt: "",
                online => ($type eq 'Online')? $amt: "",
                pname  => $p->pname,
            };
        }
    }
    @payments = sort {
                        $a->{name} cmp $b->{name}
                    }
                    @payments;
    $c->stash->{payments} = \@payments;
    $c->stash->{cash}     = $cash;
    $c->stash->{check}    = $check;
    $c->stash->{credit}   = $credit;
    $c->stash->{online}   = $online;
    $c->stash->{total}    = $total;
    $c->stash->{template} = "finance/deposit.tt2";
}

sub new_deposit_do : Local {
    my ($self, $c) = @_;
}

sub deposits : Local {
    my ($self, $c) = @_;

    $c->stash->{deposits} = 0;  # ???
    $c->stash->{template} = "finance/prior_deposits.tt2";
}

1;
