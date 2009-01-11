use strict;
use warnings;
package RetreatCenter::Controller::HouseCost;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.

use Util qw/empty model/;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{housecosts} = [
        model($c, 'HouseCost')->search(
            undef,
            {
                order_by => 'name',
            },
        )
    ];
    $c->stash->{template} = "housecost/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    my $hc = model($c, 'HouseCost')->find($id);
    if ($hc->name eq 'Default') {
        $c->stash->{template} = "housecost/nodel_default.tt2";
        return;
    }
    if (my @programs = $hc->programs()) {
        $c->stash->{housecost} = $hc;
        $c->stash->{programs} = \@programs;
        $c->stash->{template} = "housecost/cannot_del.tt2";
        return;
    }
    model($c, 'HouseCost')->search({id => $id})->delete();
    $c->response->redirect($c->uri_for('/housecost/list'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $hc = $c->stash->{housecost} = 
        model($c, 'HouseCost')->find($id);
    my $type = $hc->type();
    $c->stash->{checked_perday} = ($type eq "Per Day")? "checked": "";
    $c->stash->{checked_total}  = ($type eq "Total" )? "checked": "";
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "housecost/create_edit.tt2";
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    @mess = ();
    if (empty($hash{name})) {
        push @mess, "Missing housing cost name.";
    }
    for my $k (keys %hash) {
        next if $k eq "name" || $k eq "type";
        next if empty($hash{$k}) || $hash{$k} =~ m{^\s*\d+\s*$};
        push @mess, "Invalid cost for \u$k: $hash{$k}";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template}    = "housecost/error.tt2";
    }
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;
    model($c, 'HouseCost')->find($id)->update(\%hash);
    $c->response->redirect($c->uri_for('/housecost/list'));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{housecost} = model($c, 'HouseCost')->find($id);
    $c->stash->{template}  = "housecost/view.tt2";
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{checked_perday} = "checked";
    $c->stash->{checked_total}  = "";
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "housecost/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;
    model($c, 'HouseCost')->create(\%hash);
    $c->response->redirect($c->uri_for('/housecost/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
