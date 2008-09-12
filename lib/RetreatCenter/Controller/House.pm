use strict;
use warnings;
package RetreatCenter::Controller::House;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    empty
    model
    trim
    add_config
/;
use Global qw/%string/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{rooms} = [ model($c, 'House')->search(
        { tent   => '' },
        { order_by => 'name' }
    ) ];
    $c->stash->{tents} = [ model($c, 'House')->search(
        {
            tent   => 'yes',
        },
        { order_by => 'name' }
    ) ];
    $c->stash->{template} = "house/list.tt2";
}

# ???referential integrity - watch out!
# deletion of houses will be quite rare. but still...
# both registrations, rentals and config records
# reference house_id.
sub delete : Local {
    my ($self, $c, $id) = @_;

    model($c, 'House')->find($id)->delete();
    $c->response->redirect($c->uri_for('/house/list'));
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    # since unchecked checkboxes are not sent...
    for my $f (qw/
        bath
        tent
        center
        inactive
    /) {
        $hash{$f} = "" unless exists $hash{$f};
    }
    if ($hash{center}) {
        # center implies tent
        $hash{tent} = "yes";
    }
    @mess = ();
    if (empty($hash{name})) {
        push @mess, "Name cannot be blank.";
    }
    for my $f (qw/
        max
        x
        y
        priority
        cluster_order
    /) {
        $hash{$f} = trim($hash{$f});
        if (!($hash{$f} =~ m{^\d+$})) {
            push @mess, "Illegal \u$f: $hash{$f}";
        }
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "house/error.tt2";
    }
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $h = $c->stash->{house} = model($c, 'House')->find($id);
    $c->stash->{bath}     = $h->bath  ? "checked": "";
    $c->stash->{tent}     = $h->tent  ? "checked": "";
    $c->stash->{center}   = $h->center? "checked": "";
    $c->stash->{inactive} = $h->inactive? "checked": "";
    $c->stash->{cluster_opts} =
        [ model($c, 'Cluster')->search(
            undef,
            { order_by => 'name' },
        ) ];
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "house/create_edit.tt2";
}

#
# currently there's no way to know which fields changed
# so assume they all did.
#
# check for dups???
#
sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;
    model($c, 'House')->find($id)->update(\%hash);
    $c->response->redirect($c->uri_for('/house/list'));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{cluster_opts} =
        [ model($c, 'Cluster')->search(
            undef,
            { order_by => 'name' },
        ) ];
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "house/create_edit.tt2";
}

#
# check for dups???
#
sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;
    my $house = model($c, 'House')->create(\%hash);
    Global->init($c);
    add_config($c, $string{sys_last_config_date}, $house);
    $c->response->redirect($c->uri_for('/house/list'));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{house} = model($c, 'House')->find($id);
    $c->stash->{template} = "house/view.tt2";
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
