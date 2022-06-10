use strict;
use warnings;
package RetreatCenter::Controller::Inquiry;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    model
    stash
/;
use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{inquiries} = [ model($c, 'Inquiry')->search(
        undef,
        { order_by => 'the_date desc, the_time desc' }
    ) ];
    $c->stash->{template} = "inquiry/list.tt2";
}

sub view : Local {
    my ($self, $c, $id) = @_;
    my $i = model($c, 'Inquiry')->find($id);
    stash($c,
        inquiry  => $i,
        template => 'inquiry/view.tt2',
    );
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Inquiry')->find($id);
    _del($c, $id);
    $c->response->redirect($c->uri_for('/inquiry/list'));
}

sub del_confirm : Local {
    my ($self, $c, $id) = @_;

    if ($c->request->params->{yes}) {
        _del($c, $id);
    }
    $c->response->redirect($c->uri_for('/inquiry/list'));
}

sub _del {
    my ($c, $id) = @_;

    model($c, 'Inquiry')->search({id => $id})->delete();
}

sub update : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{inquiry}       = model($c, 'Inquiry')->find($id);
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "inquiry/create_edit.tt2";
}

#
# check for dups???
#
sub update_do : Local {
    my ($self, $c, $id) = @_;

    my $descr = $c->request->params->{descr};
    my $glnum = $c->request->params->{glnum};
    if (empty($descr)) {
        $c->stash->{mess} = "Inquiry description cannot be blank.";
        $c->stash->{template} = "inquiry/error.tt2";
        return;
    }
    if (empty($glnum)) {
        $c->stash->{mess} = "Inquiry GL Number cannot be blank.";
        $c->stash->{template} = "inquiry/error.tt2";
        return;
    }
    model($c, 'Inquiry')->find($id)->update({
        descr => $descr,
        glnum => $glnum,
    });
    $c->response->redirect($c->uri_for('/inquiry/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
