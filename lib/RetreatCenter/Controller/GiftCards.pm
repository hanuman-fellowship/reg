use strict;
use warnings;
package RetreatCenter::Controller::GiftCards;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Date::Simple qw/
    date
    today
/;
use Time::Simple qw/
    get_time
/;
use Util qw/
    model
    stash
    trim
    error
/;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

#
# default - only show cards with a balance
# if 'all' - show all including those that have been fully used.
#
sub list : Local {
    my ($self, $c, $all) = @_;

    my @cards = model($c, 'GiftCards')->search(
                    {},
                    { 
                        order_by => 'code,
                        the_date asc,
                        the_time asc',
                    },
                );
    my $prev_code = '';
    my %balance_for;
    my @gift_cards;
    my @history;
    my $total = 0;
    for my $c (@cards) {
        if ($c->code ne $prev_code) {
            if ($prev_code) {
                push @gift_cards, {
                         code => $prev_code,
                         balance => $balance_for{$prev_code},
                         history => [
                            @history,
                         ],
                     }
            }
            $prev_code = $c->code;
            @history = ();
        }
        my $amount = $c->amount;
        if ($amount > 0) {
            $total += $amount;
        }
        push @history, {
            amount => $amount,
            what   => join(' ', $c->rec_fname, $c->rec_lname, $c->rec_email),
            date   => date($c->the_date),
            time   => get_time($c->the_time),
        };
        $balance_for{$c->code} += $c->amount;
    }
    my $remaining = 0;
    for my $c (keys %balance_for) {
        $remaining += $balance_for{$c};
    }
    if ($prev_code) {
        push @gift_cards, {
                 code => $prev_code,
                 balance => $balance_for{$prev_code},
                 history => [
                    @history,
                 ],
             }
    }
    if (! $all) {
        @gift_cards = grep { $balance_for{$_->{code}} } @gift_cards;
    }
    stash($c,
        all        => $all,
        gift_cards  => \@gift_cards,
        count => (scalar keys %balance_for),
        total => $total,
        remaining => $remaining,
        template   => "gift_cards/list.tt2",
    );
}

sub add : Local {
    my ($self, $c, $code) = @_;
    stash($c,
        code     => $code,
        template => 'gift_cards/add.tt2',
    );
}

sub add_do : Local {
    my ($self, $c, $code) = @_;
    my $amount = trim($c->request->params->{amount});
    if ($amount !~ m{\A [-]?\d+ \z}xms) {
        error($c,
            'Invalid amount',
            'gen_error.tt2',
        );
        return;
    }
    # verify amount
    model($c, 'GiftCards')->create({
        code => $code,
        amount => $amount,
        person_id   => 0,
        rec_fname   => 'Manual addition',
        rec_lname   => '',
        rec_email   => '',
        the_date    => today()->as_d8(),
        the_time    => get_time()->t24,
        transaction_id => 0,
        reg_id      => 0,
    });
    # need the ' below - otherwise the & is interpreted by the shell :(
    my $status = qx(/usr/bin/curl -k 'https://www.mountmadonna.org/cgi-bin/gift_add?code=$code&amount=$amount&passwd=soma' 2>/dev/null);
    $c->response->redirect($c->uri_for("/giftcards/list"));
}

1;
