use strict;
use warnings;
package RetreatCenter::Controller::HousingType;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    model
    stash
    error
/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    my @housing_types = sort {
                            $a->ht_order <=> $b->ht_order
                        }
                        model($c, 'HousingType')->all();
    stash($c,
        housing_types => \@housing_types,
        template => "housing_type/list.tt2",
    );
}

sub update : Local {
    my ($self, $c, $name) = @_;

    my ($ht) = model($c, 'HousingType')->search(
                   { name => $name },
               );
    stash($c,
        ht       => $ht,
        template => "housing_type/update.tt2",
    );
}

sub update_do : Local {
    my ($self, $c, $name) = @_;

    model($c, 'HousingType')->search({
        name => $name,
    })->update({
        ht_order => $c->request->params->{ht_order},
        short_desc => $c->request->params->{short_desc},
        long_desc => $c->request->params->{long_desc},
    });
    $c->response->redirect($c->uri_for('/housingtype/list'));
}

1;
