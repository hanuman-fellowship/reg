use strict;
use warnings;
package RetreatCenter::Controller::Glossary;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    model
    stash
/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    stash($c,
        glossary => [ model($c, 'Glossary')->search(
            { },
            { order_by => 'term' }
        ) ],
        template     => "glossary/list.tt2",
    );
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    model($c, 'Glossary')->find($id)->delete();
    $c->response->redirect($c->uri_for('/glossary/list'));
}

sub update : Local {
    my ($self, $c, $term) = @_;

    stash($c,
        glossary    => model($c, 'Glossary')->find($term),
        form_action => "update_do/$term",
        template    => "glossary/create_edit.tt2",
    );
}

sub update_do : Local {
    my ($self, $c, $term) = @_;

    model($c, 'Glossary')->find($term)->update({
        term       => $c->request->params->{term},
        definition => $c->request->params->{definition},
    });
    $c->response->redirect($c->uri_for('/glossary/list'));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "glossary/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    my $glossary = model($c, 'Glossary')->create({
        term       => $c->request->params->{term},
        definition => $c->request->params->{definition},
    });
    $c->response->redirect($c->uri_for('/glossary/list'));
}

1;
