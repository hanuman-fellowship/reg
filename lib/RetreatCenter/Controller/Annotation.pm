use strict;
use warnings;
package RetreatCenter::Controller::Annotation;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    empty
    model
/;
use Global qw/
    %string
/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{annotations} = [ model($c, 'Annotation')->search(
        undef,
        { order_by => 'label' }
    ) ];
    $c->stash->{template} = "annotation/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    model($c, 'Annotation')->search({id => $id})->delete();
    Global->init($c, 1);
    $c->response->redirect($c->uri_for('/annotation/list'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $ann = $c->stash->{annotation}  = model($c, 'Annotation')->find($id);
    my $cluster_type_opts = "";
    for my $i (1 .. 5) {
        my $s = $string{"dp_type$i"};
        if ($s ne "future use") {
            my $selected = ($ann->cluster_type() eq $s)? "selected": "";
            $cluster_type_opts .= "<option value=$s $selected>\u$s\n";
        }
    }
    $c->stash->{cluster_type_opts} = $cluster_type_opts;
    my $shape_opts = "";
    for my $s (qw/ none rectangle filledRectangle ellipse filledEllipse /) {
        my $selected = ($s eq $ann->shape())? "selected": "";
        $shape_opts .= "<option value=$s $selected>\u$s\n";
    }
    $c->stash->{shape_opts} = $shape_opts;
    $c->stash->{check_inactive} = ($ann->inactive())? "checked": "";
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "annotation/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    my $label = $c->request->params->{label};
    my $shape = $c->request->params->{shape};
    if (empty($label)) {
        $c->stash->{mess} = "Annotations must have a label.";
        $c->stash->{template} = "annotation/error.tt2";
        return;
    }
    my %hash = %{ $c->request->params() };
    # since unchecked boxes are not sent...
    $hash{inactive} = "" unless exists $hash{inactive};
    model($c, 'Annotation')->find($id)->update(\%hash);
    Global->init($c, 1);
    $c->response->redirect($c->uri_for('/annotation/list'));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{form_action} = "create_do";
    my $cluster_type_opts = "";
    for my $i (1 .. 5) {
        my $s = $string{"dp_type$i"};
        if ($s ne "future use") {
            $cluster_type_opts .= "<option value=$s>\u$s\n";
        }
    }
    $c->stash->{cluster_type_opts} = $cluster_type_opts;
    $c->stash->{shape_opts} = <<"EOO";
<option value=none>None
<option value=rectangle>Rectangle
<option value=ellipse>Ellipse
EOO
    $c->stash->{check_inactive} = "";
    $c->stash->{template}    = "annotation/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    my $label = $c->request->params->{label};
    my $shape = $c->request->params->{shape};
    if (empty($label)) {
        $c->stash->{mess} = "Annotations must have a label.";
        $c->stash->{template} = "annotation/error.tt2";
        return;
    }
    my %hash = %{ $c->request->params() };
    $hash{inactive} = "" unless exists $hash{inactive};
    model($c, 'Annotation')->create(\%hash);
    Global->init($c, 1);
    $c->response->redirect($c->uri_for('/annotation/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
