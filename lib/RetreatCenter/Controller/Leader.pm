use strict;
use warnings;
package RetreatCenter::Controller::Leader;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/trim/;
use Lookup;

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
        $c->model('RetreatCenterDB::Leader')->all()
    ];
    $c->stash->{template} = "leader/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    $c->model('RetreatCenterDB::Leader')->search({id => $id})->delete();
    $c->response->redirect($c->uri_for('/leader/list'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $l = $c->stash->{leader} = 
        $c->model('RetreatCenterDB::Leader')->find($id);
    $c->stash->{person} = $l->person();
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "leader/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    my $leader =  $c->model("RetreatCenterDB::Leader")->find($id);
    my @upd = ();
    if (my $upload = $c->request->upload('image')) {
        chdir "root/static/images";
        $upload->copy_to("lo-$id.jpg");
        #
        # invoke ImageMagick convert to create th-$id.jpg and b-$id.jpg
        #
        Lookup->init($c);
        system("convert -scale $lookup{imgwidth}x lo-$id.jpg lth-$id.jpg");
        system("convert -scale $lookup{big_imgwidth}x lo-$id.jpg lb-$id.jpg");
        unlink "lo-$id.jpg";
        chdir "../../..";       # must cd back!   not stateless HTTP, exactly
        @upd = (image => 'yes');
    }
    my $url = $c->request->params->{url};
    $url =~ s{^\s*http://}{};
    $leader->update({
        public_email => trim($c->request->params->{public_email}),
        url          => $url,
        biography    => $c->request->params->{biography},
        @upd,
    });
    # the person_id will not change here...
    $c->response->redirect($c->uri_for("/leader/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $l = $c->stash->{leader}
        = $c->model("RetreatCenterDB::Leader")->find($id);
    my $bio = $l->biography();
    $bio =~ s{\r?\n}{<br>\n}g if $bio;
    $c->stash->{biography} = $bio;
    $c->stash->{template} = "leader/view.tt2";
}

sub create : Local {
    my ($self, $c, $person_id) = @_;

    $c->stash->{person}
        = $c->model("RetreatCenterDB::Person")->find($person_id);
    $c->stash->{form_action} = "create_do/$person_id";
    $c->stash->{template}    = "leader/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c, $person_id) = @_;

    my $upload = $c->request->upload('image');
    my $url = $c->request->params->{url};
    $url =~ s{^\s*http://}{};
    my $l = $c->model("RetreatCenterDB::Leader")->create({
        person_id    => $person_id,
        public_email => trim($c->request->params->{public_email}),
        image        => $upload? "yes": "",
        url          => $url,
        biography    => $c->request->params->{biography},
    });
    my $id = $l->id();      # the new leader id
    if ($upload) {
        chdir "root/static/images";
        $upload->copy_to("lo-$id.jpg");
        #
        # invoke ImageMagick convert to create th-$id.jpg and b-$id.jpg
        #
        system("convert -scale 150x lo-$id.jpg lth-$id.jpg");
        system("convert -scale 600x lo-$id.jpg lb-$id.jpg");
        chdir "../../..";
    }
    $c->response->redirect($c->uri_for("/leader/view/$id"));
}

sub del_image : Local {
    my ($self, $c, $id) = @_;

    my $l = $c->stash->{leader}
        = $c->model("RetreatCenterDB::Leader")->find($id);
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
