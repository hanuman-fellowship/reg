use strict;
use warnings;

package RetreatCenter::Controller::String;
use base 'Catalyst::Controller';

use Global qw/
    %string
/;
use Util qw/
    resize
    model
/;
use Date::Simple;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c, $colors) = @_;

    my @colors = ();
    if ($colors) {
        push @colors, the_key => { -like => '%color%' };
    }
    else {
        push @colors, the_key => { -not_like => '%color%' };
    }
    $c->stash->{strings} = [ model($c, 'String')->search(
        { 
            the_key => { -not_like => 'sys_%' },
            @colors,
        },
        {
            order_by => 'the_key'
        },
    ) ];
    $c->stash->{template} = "string/list.tt2";
}

use URI::Escape;
sub update : Local {
    my ($self, $c, $the_key) = @_;

    my $s = model($c, 'String')->find($the_key);

    $c->stash->{the_key} = $the_key;
    my $value = $c->stash->{value} = uri_escape($s->value, '"');
    $c->stash->{form_action} = "update_do/$the_key";
    if ($the_key =~ m{_color$}) {
        my ($r, $g, $b) = $value =~ m{\d+}g;
        $c->stash->{red}   = $r;
        $c->stash->{green} = $g;
        $c->stash->{blue}  = $b;
        $c->stash->{template}    = "string/create_edit_color.tt2";
    }
    else {
        $c->stash->{template}    = "string/create_edit.tt2";
    }
}

sub update_do : Local {
    my ($self, $c, $the_key) = @_;

    my $value = uri_unescape($c->request->params->{value});
    model($c, 'String')->find($the_key)->update({
        value => $value,
    });
    $string{$the_key} = $value;
    if ($the_key =~ m{imgwidth} && $c->request->params->{resize_all}) {
        for my $f (<root/static/images/*o-*.jpg>) {
            my ($type, $id) = $f =~ m{/(\w+)o-(\d+).jpg$};
            resize($type, $id, $the_key);
        }
    }
    if ($the_key eq 'default_date_format') {
        Date::Simple->default_format($value);
    }
    if ($the_key =~ m{color}) {
        $c->response->redirect($c->uri_for("/string/list/1/#$the_key"));
    }
    else {
        $c->response->redirect($c->uri_for("/string/list#$the_key"));
    }
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
