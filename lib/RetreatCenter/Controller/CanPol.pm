use strict;
use warnings;
package RetreatCenter::Controller::CanPol;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    empty
    model
    read_only
/;

#
# ??? at the last minute I found that I didn't check
# for blank CanPol names or policies.   The name IS
# marked with an red asterisk so it should (obviously) not be blank
# but the policy itself as well.   I'll leave this as
# something that Adrienne can find!   When she finds it and you
# fix it do the usual _get_data() @mess, %hash thing.
#

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{canpols} = [
        model($c, 'CanPol')->search(
            undef,
            {
                order_by => 'name',
            },
        )
    ];
    $c->stash->{template} = "canpol/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    my $cp = model($c, 'CanPol')->find($id);
    if ($cp->name eq 'Default') {
        $c->stash->{template} = "canpol/nodel_default.tt2";
        return;
    }
    if (my @programs = $cp->programs()) {
        $c->stash->{canpol}   = $cp;
        $c->stash->{programs} = \@programs;
        $c->stash->{template} = "canpol/cannot_del.tt2";
        return;
    }
    model($c, 'CanPol')->search({id => $id})->delete();
    $c->response->redirect($c->uri_for('/canpol/list'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    $c->stash->{canpol}      = model($c, 'CanPol')->find($id);
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "canpol/create_edit.tt2";
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    @mess = ();
    if (empty($hash{name})) {
        push @mess, "Missing name";
    }
    if (empty($hash{policy})) {
        push @mess, "Missing policy";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>", @mess;
        $c->stash->{template} = "canpol/error.tt2";
    }
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;
    model($c, 'CanPol')->find($id)->update({
        name   => $c->request->params->{name},
        policy => $c->request->params->{policy},
    });
    $c->response->redirect($c->uri_for('/canpol/list'));
}

sub create : Local {
    my ($self, $c) = @_;

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "canpol/create_edit.tt2";
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $cp = $c->stash->{canpol} = model($c, 'CanPol')->find($id);
    $c->stash->{template} = "canpol/view.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;
    model($c, 'CanPol')->create({
        name   => $c->request->params->{name},
        policy => $c->request->params->{policy},
    });
    $c->response->redirect($c->uri_for('/canpol/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
