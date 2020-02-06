use strict;
use warnings;
package RetreatCenter::Controller::GiftCards;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;
use Util qw/
    model
    stash
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

    my @gift_cards = map {
                         +{
                             code => $_->code,
                             amount => $_->amount,
                             date => date($_->the_date),
                             time => get_time($_->the_time),
                         }
                     }
                     model($c, 'GiftCards')->search(
                         {},
                         { 
                            order_by => 'code,
                            the_date asc,
                            the_time asc',
                         },
                     );
    my %balance_for;
    for my $gc (@gift_cards) {
        $balance_for{$gc->{code}} += $gc->{amount};
    }
    if (! $all) {
        @gift_cards = grep { $balance_for{$_->{code}} } @gift_cards;
    }
    stash($c,
        all        => $all,
        gift_cards  => \@gift_cards,
        template   => "gift_cards/list.tt2",
    );
}

1;
