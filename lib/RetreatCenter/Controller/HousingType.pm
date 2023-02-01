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
    my $dir = '/var/www/src/root/static/images';
    stash($c,
        pic1     => -f "$dir/${name}1.jpg",
        pic2     => -f "$dir/${name}2.jpg",
        ht       => $ht,
        template => "housing_type/update.tt2",
    );
}

my $images = '/var/www/src/root/static/images';

sub update_do : Local {
    my ($self, $c, $name) = @_;

    my %P = %{ $c->request->params() };
    model($c, 'HousingType')->search({
        name => $name,
    })->update({
        ht_order   => $P{ht_order},
        short_desc => $P{short_desc},
        long_desc  => $P{long_desc},
    });
    for my $i (1, 2) {
        my $upload = $c->request->upload("pic$i");
        if ($upload) {
            # force the name to be .jpg even if it's a .png...
            # okay?
            $upload->copy_to("$images/$name$i.jpg");
        }
    }
    $c->response->redirect($c->uri_for('/housingtype/list'));
}

sub del_image :Local {
    my ($self, $c, $name, $i) = @_;
    unlink "$images/$name$i.jpg";
    $c->response->redirect($c->uri_for('/housingtype/list'));
}

1;
