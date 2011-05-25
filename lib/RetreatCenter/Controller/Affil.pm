use strict;
use warnings;
package RetreatCenter::Controller::Affil;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    empty
    model
    main_mmi_affil
/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{affil} = [ model($c, 'Affil')->search(
        undef,
        { order_by => 'descrip' }
    ) ];
    $c->stash->{ok_del_edit} = sub {
        my $descrip = shift;
        return ! ($descrip =~ m{\b(alert|guru)\b}ixms
                  ||
                  main_mmi_affil($descrip)
                 );
    };
    $c->stash->{template} = "affil/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    #
    # first, are there any programs, people or reports
    # with this affiliation?  If so, show them and get confirmation 
    # before doing the deletion.
    #
    my $a = model($c, 'Affil')->find($id);
    my @people   = $a->people();
    my @programs = $a->programs();
    my @reports  = $a->reports();

    if (@people || @programs || @reports) {
        $c->stash->{affil}    = $a;
        $c->stash->{people}   = \@people   if @people;
        $c->stash->{programs} = \@programs if @programs;
        $c->stash->{reports}  = \@reports  if @reports;
        $c->stash->{template} = "affil/del_confirm.tt2";
        return;
    }
    _del($c, $id);
    $c->response->redirect($c->uri_for('/affil/list'));
}

sub del_confirm : Local {
    my ($self, $c, $id) = @_;

    if ($c->request->params->{yes}) {
        _del($c, $id);
    }
    $c->response->redirect($c->uri_for('/affil/list'));
}

sub _del {
    my ($c, $id) = @_;

    model($c, 'Affil')->search({id => $id})->delete();
    model($c, 'AffilPerson')->search({a_id => $id})->delete();
    model($c, 'AffilProgram')->search({a_id => $id})->delete();
    model($c, 'AffilReport')->search(
        {affiliation_id => $id})->delete();
}

sub update : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{affil}       = model($c, 'Affil')->find($id);
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "affil/create_edit.tt2";
}

#
# currently there's no way to know which fields changed
# so assume they all did.
#
# check for dups???
#
sub update_do : Local {
    my ($self, $c, $id) = @_;

    my $descrip = $c->request->params->{descrip};
    if (empty($descrip)) {
        $c->stash->{mess} = "Affiliation description cannot be blank.";
        $c->stash->{template} = "affil/error.tt2";
        return;
    }
    model($c, 'Affil')->find($id)->update({
        descrip => $descrip,
    });
    $c->response->redirect($c->uri_for('/affil/list'));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "affil/create_edit.tt2";
}

#
# check for dups???
#
sub create_do : Local {
    my ($self, $c) = @_;

    my $descrip = $c->request->params->{descrip};
    if (empty($descrip)) {
        $c->stash->{mess} = "Affiliation description cannot be blank.";
        $c->stash->{template} = "affil/error.tt2";
        return;
    }
    model($c, 'Affil')->create({
        descrip => $descrip,
    });
    $c->response->redirect($c->uri_for('/affil/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
