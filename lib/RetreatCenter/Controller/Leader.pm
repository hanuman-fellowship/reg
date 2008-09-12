use strict;
use warnings;
package RetreatCenter::Controller::Leader;
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

    $c->stash->{leaders} = [
        # how to sort like this in all()???
        sort {
            $a->person->last()  cmp $b->person->last()
            or
            $a->person->first() cmp $b->person->first()
        }
        model($c, 'Leader')->all()
    ];
    $c->stash->{template} = "leader/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    my $l = model($c, 'Leader')->find($id);
    if (my @programs = $l->programs()) {
        $c->stash->{leader} = $l;
        $c->stash->{programs} = \@programs;
        $c->stash->{template} = "leader/del_confirm.tt2";
        return;
    }
    _del($c, $id);
    $c->response->redirect($c->uri_for('/leader/list'));
}

sub del_confirm : Local {
    my ($self, $c, $id) = @_;

    if ($c->request->params->{yes}) {
        _del($c, $id);
    }
    $c->response->redirect($c->uri_for('/leader/list'));
}

sub _del {
    my ($c, $id) = @_;
    model($c, 'Leader')->search({id => $id})->delete();
    model($c, 'LeaderProgram')->search({l_id => $id})->delete();
    unlink <root/static/images/l*-$id.jpg>;
}

my @mess;
my %hash;
sub _get_data {
    my ($c) = @_;
    
    @mess = ();
    %hash = ();
    for my $f (qw/
        public_email
        l_order
        url
        biography
    /) {
        $hash{$f} = trim($c->request->params->{$f});
    }
    if ($hash{public_email} && ! valid_email($hash{public_email})) {
        push @mess, "Invalid email address: $hash{public_email}";
    }
    if ($hash{l_order} !~ m{^\d+}) {
        push @mess, "Illegal order: $hash{l_order}";
    }
    if (@mess) {
        $c->stash->{mess}     = join "<br>\n", @mess;
        $c->stash->{template} = "leader/error.tt2";
        return;
    }
    $hash{url} =~ s{^http://}{};
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $l = $c->stash->{leader} = model($c, 'Leader')->find($id);
    $c->stash->{person} = $l->person();
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "leader/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;
    my @img = ();
    if (my $upload = $c->request->upload('image')) {
        $upload->copy_to("root/static/images/lo-$id.jpg");
        Global->init($c);
        resize('l', $id);
        @img = (image => 'yes');
    }
    model($c, 'Leader')->find($id)->update({
        %hash,
        @img,
    });
    $c->response->redirect($c->uri_for("/leader/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $l = $c->stash->{leader} = model($c, 'Leader')->find($id);
    $c->stash->{template} = "leader/view.tt2";
}

sub create : Local {
    my ($self, $c, $person_id) = @_;

    $c->stash->{person}      = model($c, 'Person')->find($person_id);
    $c->stash->{form_action} = "create_do/$person_id";
    $c->stash->{leader}      = { l_order => 1 };  # fake a Leader object
                                                  # for this default
    $c->stash->{template}    = "leader/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c, $person_id) = @_;

    _get_data($c);
    return if @mess;
    my $l = model($c, 'Leader')->create({
        person_id => $person_id,
        %hash,
    });
    my $id = $l->id();      # the new leader id
    my $upload = $c->request->upload('image');
    if ($upload) {
        $upload->copy_to("root/static/images/lo-$id.jpg");
        Global->init($c);
        resize('l', $id);
        $l->update({
            image => 'yes',
        });
    }
    $c->response->redirect($c->uri_for("/leader/view/$id"));
}

sub del_image : Local {
    my ($self, $c, $id) = @_;

    my $l = $c->stash->{leader} = model($c, 'Leader')->find($id);
    $l->update({
        image => "",
    });
    unlink <root/static/images/l*-$id.jpg>;
    $c->response->redirect($c->uri_for("/leader/view/$id"));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
