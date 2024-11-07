use strict;
use warnings;
package RetreatCenter::Controller::HousingType;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    model
    stash
    error
    read_only
/;
use File::Copy qw/
    move
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

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    my ($ht) = model($c, 'HousingType')->search(
                   { name => $name },
               );
    my $dir = '/var/www/src/root/static/images';
    my @pics;
    for my $i (1 .. 4) {
        push @pics, "pic$i" => -f "$dir/${name}$i.jpg";
    }
    stash($c,
        @pics,
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
    for my $i (1 .. 4) {
        my $upload = $c->request->upload("pic$i");
        if ($upload) {
            # force the name to be .jpg even if it's a .png...
            # okay?
            my $pic = "$images/$name$i.jpg";
            my $tmp = '/tmp/pic.jpg';
            $upload->copy_to($pic);
            system("/usr/bin/convert $pic -resize 450x $tmp");
            move $tmp, $pic;
        }
    }
    $c->response->redirect($c->uri_for('/housingtype/list'));
}

sub del_image :Local {
    my ($self, $c, $name, $i) = @_;

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    unlink "$images/$name$i.jpg";
    $c->response->redirect($c->uri_for('/housingtype/list'));
}

1;
