use strict;
use warnings;

package RetreatCenter::Controller::Exception;
use base 'Catalyst::Controller';

#
# a good initial list
#
my @tags = sort qw/
    title1
    title2
    title1_barnacles
    prog_dates_style
    title2_barnacles
    barnacles
    webdesc_plus
    weburl
    month_calendar
    fee_table
    firstprog_prevmonth
    firstprog_nextmonth
    prevprog
    nextprog
    cancellation_policy
    dates
    dates_tr
    dates_tr2
    leaders
    leader_bio
    picture
/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    my @exs = sort {
                  $a->program->name cmp $b->program->name ||
                  $a->tag           cmp $b->tag
              }
              $c->model('RetreatCenterDB::Exception')->all();
    $c->stash->{exceptions} = \@exs;
    $c->stash->{template} = "exception/list.tt2";
}

sub delete : Local {
    my ($self, $c, $prog_id, $tag) = @_;

    $c->model('RetreatCenterDB::Exception')->search(
        {
            prog_id => $prog_id,
            tag     => $tag,
        }
    )->delete();
    $c->response->redirect($c->uri_for('/exception/list'));
}

sub update : Local {
    my ($self, $c, $prog_id, $tag) = @_;

    my @e = $c->model('RetreatCenterDB::Exception')->search(
        {
            prog_id => $prog_id,
            tag     => $tag,
        }
    );
    $c->stash->{exception} = $e[0];
    $c->stash->{programs} = [ $c->model("RetreatCenterDB::Program")->search(
        undef,
        { order_by => 'name' },
    ) ];
    $c->stash->{tags} = \@tags;
    $c->stash->{form_action} = "update_do/$prog_id/$tag";
    $c->stash->{template}    = "exception/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $prog_id, $tag) = @_;

    $c->model("RetreatCenterDB::Exception")->search(
        {
            prog_id => $prog_id,
            tag     => $tag,
        }
    )->update({
        prog_id => $c->request->params->{prog_id},
        tag     => $c->request->params->{tag},
        value   => $c->request->params->{value},
    });
    $c->response->redirect($c->uri_for('/exception/list'));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{programs} = [ $c->model("RetreatCenterDB::Program")->search(
        undef,
        { order_by => 'name' },
    ) ];
    $c->stash->{tags} = \@tags;
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "exception/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    $c->model("RetreatCenterDB::Exception")->create({
        prog_id => $c->request->params->{prog_id},
        tag     => $c->request->params->{tag},
        value   => $c->request->params->{value},
    });
    $c->response->redirect($c->uri_for('/exception/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
