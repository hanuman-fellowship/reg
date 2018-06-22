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
    stash
/;
use Global qw/%string/;     # resize needs this to have been done

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c, $inactive) = @_;

    my @leaders = model($c, 'Leader')->search(
            {
                'me.inactive' => ($inactive? 'yes': ''),
            },
            {
                prefetch => [qw/ person /],
                order_by => [qw/ person.last person.first /],
            },
    );
    stash($c,
        leaders  => \@leaders,
        inactive => $inactive,
        template => 'leader/list.tt2',
    );
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    my $l = model($c, 'Leader')->find($id);
    if (my @programs = $l->programs()) {
        stash($c,
            leader    => $l,
            programs  => \@programs,
            template  => 'leader/del_confirm.tt2',
        );
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
        assistant
        inactive
        just_first
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
        stash($c,
            mess     => join("<br>\n", @mess),
            template => "leader/error.tt2",
        );
        return;
    }
    $hash{url} =~ s{^http://}{};

    # since not sent if not checked...
    $hash{assistant}  = '' unless $hash{assistant};
    $hash{just_first} = '' unless $hash{just_first};
    $hash{inactive}   = '' unless $hash{inactive};
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $l = model($c, 'Leader')->find($id);
    stash($c,
        leader => $l,
        person => $l->person(),
        form_action       => "update_do/$id",
        check_assistant   => ($l->assistant )? "checked": "",
        check_just_first  => ($l->just_first)? "checked": "",
        check_inactive    => ($l->inactive  )? "checked": "",
        template          => "leader/create_edit.tt2",
    );
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

    stash($c,
        leader   => model($c, 'Leader')->find($id),
        template => 'leader/view.tt2',
    );
}

sub create : Local {
    my ($self, $c, $person_id) = @_;

    stash($c,
        person      => model($c, 'Person')->find($person_id),
        form_action => "create_do/$person_id",
        leader      => { l_order => 1 },  # fake a Leader object
                                          # for this default
        check_assistant => '',
        check_inactive  => '',
        just_first      => '',
        inactive        => '',
        template        => "leader/create_edit.tt2",
    );
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

    model($c, 'Leader')->find($id)->update({
        image => "",
    });
    unlink <root/static/images/l*-$id.jpg>;
    $c->response->redirect($c->uri_for("/leader/view/$id"));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    stash($c,
        mess     => 'Authorization denied!',
        template => 'gen_error.tt2',
    );
}

1;
