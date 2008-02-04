use strict;
use warnings;
package RetreatCenter::Controller::Template;
use base 'Catalyst::Controller';

use Util qw/sys_template model/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{templates} = [
        map {
            {
                name   => $_,
                delete => ! sys_template($_),
            }
        }
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

    if (my @programs = model($c, 'Program')->search({
                                 ptemplate => $fname,
                                })
    ) {
        $c->stash->{ptemplate} = $fname;
        $c->stash->{programs} = \@programs;
        $c->stash->{template} = "template/cannot_del.tt2";
        return;
    }
    unlink "root/static/templates/$fname.html";
    $c->response->redirect($c->uri_for('/template/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
