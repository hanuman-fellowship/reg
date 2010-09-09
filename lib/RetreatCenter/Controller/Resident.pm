use strict;
use warnings;
package RetreatCenter::Controller::Resident;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    trim
    resize
    valid_email
    model
/;
use Global qw/%string/;     # resize needs this to have been done

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{residents} = [
        # how to sort like this in all()???
        sort {
            $a->person->last()  cmp $b->person->last()
            or
            $a->person->first() cmp $b->person->first()
        }
        model($c, 'Resident')->all()
    ];
    $c->stash->{template} = "resident/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    my $r = model($c, 'Resident')->find($id);
    _del($c, $id);
    $c->response->redirect($c->uri_for('/resident/list'));
}

sub del_confirm : Local {
    my ($self, $c, $id) = @_;

    if ($c->request->params->{yes}) {
        _del($c, $id);
    }
    $c->response->redirect($c->uri_for('/resident/list'));
}

sub _del {
    my ($c, $id) = @_;
    model($c, 'Resident')->search({id => $id})->delete();
    unlink <root/static/images/r*-$id.jpg>;
}

my @mess;
my %hash;
sub _get_data {
    my ($c) = @_;
    
    @mess = ();
    %hash = ();
    for my $f (qw/
        comment
    /) {
        $hash{$f} = trim($c->request->params->{$f});
    }
    if (@mess) {
        $c->stash->{mess}     = join "<br>\n", @mess;
        $c->stash->{template} = "resident/error.tt2";
        return;
    }
    # for booleans...
    # $hash{just_first} = '' unless $hash{just_first};
            # since not sent if not checked...
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $r = $c->stash->{resident} = model($c, 'Resident')->find($id);
    $c->stash->{person} = $r->person();
    $c->stash->{form_action} = "update_do/$id";
    # booleans
    # $c->stash->{"check_just_first"}  = ($l->just_first)? "checked": "";
    $c->stash->{template}    = "resident/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;
    my @img = ();
    if (my $upload = $c->request->upload('image')) {
        $upload->copy_to("root/static/images/ro-$id.jpg");
        Global->init($c);
        resize('r', $id);
        @img = (image => 'yes');
    }
    model($c, 'Resident')->find($id)->update({
        %hash,
        @img,
    });
    $c->response->redirect($c->uri_for("/resident/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $l = $c->stash->{resident} = model($c, 'Resident')->find($id);
    $c->stash->{template} = "resident/view.tt2";
}

sub create : Local {
    my ($self, $c, $person_id) = @_;

    $c->stash->{person}      = model($c, 'Person')->find($person_id);
    $c->stash->{form_action} = "create_do/$person_id";
    $c->stash->{resident}      = { l_order => 1 };  # fake a Resident object
                                                  # for this default
    $c->stash->{template}    = "resident/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c, $person_id) = @_;

    _get_data($c);
    return if @mess;
    my $r = model($c, 'Resident')->create({
        person_id => $person_id,
        %hash,
    });
    my $id = $r->id();      # the new resident id
    my $upload = $c->request->upload('image');
    if ($upload) {
        $upload->copy_to("root/static/images/ro-$id.jpg");
        Global->init($c);
        resize('r', $id);
        $r->update({
            image => 'yes',
        });
    }
    $c->response->redirect($c->uri_for("/resident/view/$id"));
}

sub del_image : Local {
    my ($self, $c, $id) = @_;

    my $r = $c->stash->{resident} = model($c, 'Resident')->find($id);
    $r->update({
        image => "",
    });
    unlink <root/static/images/r*-$id.jpg>;
    $c->response->redirect($c->uri_for("/resident/view/$id"));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
