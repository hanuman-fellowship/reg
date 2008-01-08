use strict;
use warnings;
package RetreatCenter::Controller::Rental;
use base 'Catalyst::Controller';

use Date::Simple qw/date/;
use Util qw/trim/;

use lib '../../';       # so you can do a perl -c here.

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{check_webready} = "checked";
    $c->stash->{check_linked}   = "checked";
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "rental/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    # dates are either blank or converted to d8 format
    my @mess;
    for my $d (qw/ sdate edate /) {
        my $fld = $c->request->params->{$d};
        if (! $fld =~ /\S/) {
            push @mess, "missing date field";
            next;
        }
        my $dt = date($fld);
        if ($fld && ! $dt) {
            # tell them which date field is wrong???
            push @mess, "Invalid date: $fld";
            next;
        }
        $c->request->params->{$d} = $dt? $dt->as_d8()
                                   :     "";
    }
    if (!@mess && $c->request->params->{sdate}
                  > 
                  $c->request->params->{edate}
    ) {
        push @mess, "end date must be after the start date";
    }
    if (! $c->request->params->{title} =~ /\S/) {
        push @mess, "title cannot be blank";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "rental/error.tt2";
        return;
    }

    my %hash;
    for my $w (qw/
        name title subtitle glnum
        sdate edate url webdesc
        linked phone email
    /) {
        $hash{$w} = $c->request->params->{$w};
    }
    $hash{url} =~ s{^\s*http://}{};
    $hash{email} = trim($hash{email});
    my $p = $c->model("RetreatCenterDB::Rental")->create({
        %hash,
    });
    my $id = $p->id();
    $c->response->redirect($c->uri_for("/rental/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->stash->{rental}
        = $c->model("RetreatCenterDB::Rental")->find($id);
    for my $w (qw/ sdate edate /) {
        $c->stash->{$w} = date($p->$w) || "";
    }
    for my $w (qw/ webdesc /) {
        my $s = $p->$w();
        $s =~ s{\r?\n}{<br>\n}g if $s;
        $c->stash->{$w} = $s;
    }
    $c->stash->{template} = "rental/view.tt2";
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{rentals} = [
        $c->model('RetreatCenterDB::Rental')->search(
            undef,
            { order_by => 'title' },
        )
    ];
    $c->stash->{template} = "rental/list.tt2";
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->model('RetreatCenterDB::Rental')->find($id);
    $c->stash->{rental} = $p;
    $c->stash->{"check_linked"}  = ($p->linked())? "checked": "";
    for my $w (qw/ sdate edate /) {
        $c->stash->{$w} = date($p->$w) || "";
    }
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "rental/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    # dup'ed code - what to do???
    # dates are either blank or converted to d8 format
    my @mess;
    for my $d (qw/ sdate edate /) {
        my $fld = $c->request->params->{$d};
        if (! $fld =~ /\S/) {
            push @mess, "missing date field";
            next;
        }
        my $dt = date($fld);
        if ($fld && ! $dt) {
            # tell them which date field is wrong???
            push @mess, "Invalid date: $fld";
            next;
        }
        $c->request->params->{$d} = $dt? $dt->as_d8()
                                   :     "";
    }
    if (!@mess && $c->request->params->{sdate}
                  > 
                  $c->request->params->{edate}
    ) {
        push @mess, "end date must be after the start date";
    }
    if (! $c->request->params->{title} =~ /\S/) {
        push @mess, "title cannot be blank";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        # ??? person or program or a general error template?
        $c->stash->{template} = "person/error.tt2";
        return;
    }

    my %hash;
    for my $w (qw/
        name title subtitle glnum
        sdate edate url webdesc
        linked phone email
    /) {
        $hash{$w} = $c->request->params->{$w};
    }
    $hash{url} =~ s{^\s*http://}{};
    $hash{email} = trim($hash{email});
    my $p = $c->model("RetreatCenterDB::Rental")->find($id);
    $p->update(\%hash);
    $c->response->redirect($c->uri_for("/rental/view/" . $p->id));
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    $c->model('RetreatCenterDB::Rental')->search(
        { id => $id }
    )->delete();
    $c->response->redirect($c->uri_for('/rental/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
