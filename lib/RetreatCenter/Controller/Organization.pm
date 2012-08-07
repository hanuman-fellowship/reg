use strict;
use warnings;
package RetreatCenter::Controller::Organization;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    empty
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

    stash($c,
        organizations => [ model($c, 'Organization')->search(
                            undef,
                            { order_by => 'name' }
                        ) ],
        template => "organization/list.tt2",
    );
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    model($c, 'Organization')->find($id)->delete();
    $c->response->redirect($c->uri_for('/organization/list'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $o = model($c, 'Organization')->find($id);
    my ($r, $g, $b) = $o->color =~ m{(\d+)}g;
    stash($c,
        organization    => $o,
        red             => $r,
        green           => $g,
        blue            => $b,
        form_action  => "update_do/$id",
        template     => "organization/create_edit.tt2",
    );
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    my %data;
    for my $f (qw/ name color /) {
        $data{$f} = $c->request->params->{$f};
        if (empty($data{$f})) {
            error($c,
                "\u$f cannot be empty.",
                'gen_error.tt2',
            );
            return;
        }
    }
    my $on_prog_cal = $c->request->params->{on_prog_cal} || '';
    model($c, 'Organization')->find($id)->update({
        color       => $data{color},
        name        => $data{name},
        on_prog_cal => $on_prog_cal,
    });
    $c->response->redirect($c->uri_for('/organization/list'));
}

sub create : Local {
    my ($self, $c) = @_;

    stash($c,
        red         => 127,
        green       => 127,
        blue        => 127,
        form_action => "create_do",
        template    => "organization/create_edit.tt2",
    );
}

sub create_do : Local {
    my ($self, $c) = @_;

    my %data;
    for my $f (qw/ name color /) {
        $data{$f} = $c->request->params->{$f};
        if (empty($data{$f})) {
            error($c,
                "\u$f cannot be empty.",
                'gen_error.tt2',
            );
            return;
        }
    }
    my $on_prog_cal = $c->request->params->{on_prog_cal} || '';
    model($c, 'Organization')->create({
        color       => $data{color},
        name        => $data{name},
        on_prog_cal => $on_prog_cal,
    });
    $c->response->redirect($c->uri_for('/organization/list'));
}

1;
