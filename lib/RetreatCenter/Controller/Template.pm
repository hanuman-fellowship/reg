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

    $c->stash->{web_templates} = [
        map {
            {
                name   => $_,
                delete => ! sys_template($_),
            }
        }
        map { s{^.*templates/web/(.*)[.]html$}{$1}; $_ }
        <root/static/templates/web/*.html>
    ];
    $c->stash->{letter_templates} = [
        map {
            {
                name   => $_,
                delete => $_ ne 'default'
            }
        }
        map { s{^.*templates/letter/(.*)[.]tt2$}{$1}; $_ }
        <root/static/templates/letter/*.tt2>
    ];
    $c->stash->{template} = 'template/list.tt2';
}

sub upload : Local {
    my ($self, $c, $type) = @_;

    my $fname = $c->request->params->{"${type}_fname"};
    $fname =~ s{[.]\w+}{};
    my $upload = $c->request->upload("${type}_template_file");
    my $suf = ($type eq 'web')? 'html': 'tt2';
    $upload->copy_to("root/static/templates/$type/$fname.$suf");
    $c->response->redirect($c->uri_for('/template/list'));
}

sub delete : Local {
    my ($self, $c, $type, $fname) = @_;

    if (my @programs = model($c, 'Program')->search({
                                 ptemplate => $fname,
                                })
    ) {
        $c->stash->{ptemplate} = $fname;
        $c->stash->{programs} = \@programs;
        $c->stash->{template} = "template/cannot_del.tt2";
        return;
    }
    my $suf = ($type eq 'web')? 'html': 'tt2';
    unlink "root/static/templates/$type/$fname.$suf";
    $c->response->redirect($c->uri_for('/template/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
