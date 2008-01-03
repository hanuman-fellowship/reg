use strict;
use warnings;
package RetreatCenter::Controller::Template;
use base 'Catalyst::Controller';

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{templates} = [
        map { s{^.*templates/(.*)[.]html$}{$1}; $_ }
        <root/static/templates/*.html>
    ];
    $c->stash->{template} = 'template/list.tt2';
}

sub upload : Local {
    my ($self, $c) = @_;

    my $fname = $c->request->params->{fname};
    $fname =~ s{[.]html$}{};
    my $upload = $c->request->upload('template_file');
    $upload->copy_to("root/static/templates/$fname.html");
    $c->response->redirect($c->uri_for('/template/list'));
}

sub delete : Local {
    my ($self, $c, $fname) = @_;

    unlink "root/static/templates/$fname.html";
    $c->response->redirect($c->uri_for('/template/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
