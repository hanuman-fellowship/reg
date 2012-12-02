use strict;
use warnings;
package RetreatCenter::Controller::Affil;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    empty
    model
    main_mmi_affil
    stash
    affil_table
    error
/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    stash($c,
        affil => [ model($c, 'Affil')->search(
                       undef,
                       { order_by => 'descrip' }
                   )
        ],
        ok_del_edit => sub {
            my $descrip = shift;
            return ! ($descrip =~ m{\b(alert|guru)\b}ixms
                   ||
                   main_mmi_affil($descrip)
                   );
        },
        template => "affil/list.tt2",
    );
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

sub merge : Local {
    my ($self, $c, $id) = @_;

    stash($c,
        affil       => model($c, 'Affil')->find($id),
        affil_table => affil_table($c),
        template    => 'affil/merge.tt2',
    );
}
sub merge_confirm : Local {
    my ($self, $c, $id) = @_;

    my @cur_affils = grep { s/^aff(\d+)/$1/ }
                     $c->request->param;
    if (@cur_affils == 0) {
        error($c,
            'You did not choose an affiliation to merge into!',
            'gen_error.tt2',
        );
        return;
    }
    if (@cur_affils > 1) {
        error($c,
            'You chose more than one!',
            'gen_error.tt2',
        );
        return;
    }
    if ($cur_affils[0] == $id) {
        error($c,
            'It makes no sense to merge an affiliation into itself!',
            'gen_error.tt2',
        );
        return;
    }
    my $affil = model($c, 'Affil')->find($id);
    stash($c,
        affil      => $affil,
        into_affil => model($c, 'Affil')->find($cur_affils[0]),
        npeople    => scalar($affil->people),
        nprograms  => scalar($affil->programs),
        nreports   => scalar($affil->reports),
        template    => 'affil/merge_confirm.tt2',
    );
}
sub merge_do : Local {
    my ($self, $c, $from_id, $into_id) = @_;

    for my $model ('AffilPerson', 'AffilProgram') {
        for my $ap (model($c, $model)->search({
                       a_id => $from_id,
                    })
        ) {
            # the list vs scalar context matters for when 
            # you are doing a search...  It returns different
            # things.
            #
            my @ap = model($c, $model)->search({
                         a_id => $into_id,
                         p_id => $ap->p_id,
                     }); 
            if (@ap) {
                $ap->delete();
            }
            else {
                $ap->update({
                    a_id => $into_id,
                });
            }
        }
    }
    # Unfortunately the report table has affiliation_id not a_id so ...
    for my $ar (model($c, 'AffilReport')->search({
                   a_id => $from_id,
                })
    ) {
        my @ar = model($c, 'AffilReport')->search({
                     affiliation_id => $into_id,
                     report_id      => $ar->report_id,
                 }); 
        if (@ar) {
            $ar->delete();
        }
        else {
            $ar->update({
                affiliation_id => $into_id,
            });
        }
    }
    model($c, 'Affil')->find($from_id)->delete();

    $c->forward('list');
}

sub access_denied : Private {
    my ($self, $c) = @_;

    stash($c,
        mess     => "Authorization denied!",
        template => "gen_error.tt2",
    );
}

1;
