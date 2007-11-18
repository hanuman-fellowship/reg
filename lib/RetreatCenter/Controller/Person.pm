use strict;
use warnings;
package RetreatCenter::Controller::Person;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/affil_table trim/;
use Date::Simple qw/date today/;

Date::Simple->default_format("%D");      # set it here - where else???

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('search');
}

sub search : Local {
    my ($self, $c) = @_;

    $c->stash->{template} = "person/search.tt2";
}

sub search_do : Local {
    my ($self, $c) = @_;

    my $pattern = trim($c->request->params->{pattern});
    my $field   = $c->request->params->{field};
    my $substr  = ($c->request->params->{match} eq 'substr')? '%': '';
    my $nrecs   = $c->request->params->{nrecs};

    $c->stash->{people} = [
        $c->model('RetreatCenterDB::Person')->search(
            {
                $field => { 'like', "$substr$pattern%" },
            },
            {
                order_by => $field,
                rows     => $nrecs
            },
        )
    ];
    $c->stash->{template} = "person/search_result.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    #
    # i tried using delete_all() as directed
    # to do the cascade to the affils for this person.
    # look at the DBIC_TRACE - it does it VERY inefficiently :(.
    # delete with find() does the same.  but not with search()???.
    #
    #$c->model('RetreatCenterDB::Person')->search({id => $id})->delete_all();
    #$c->model('RetreatCenterDB::Person')->find($id)->delete();
    #
    # both the above do an inefficient delete of affils.
    # this is direct and much better:
    #$c->model('RetreatCenterDB::AffilPerson')->search({p_id => $id})->delete();
    #

    # first a find() to get the name for the message below
    my $p = $c->model('RetreatCenterDB::Person')->find($id);
    my $name = $p->first() . " " . $p->last();

    # now delete
    $c->model('RetreatCenterDB::Person')->search(
        { id => $id }
    )->delete();
    $c->model('RetreatCenterDB::AffilPerson')->search(
        { p_id => $id }
    )->delete();

    $c->flash->{status_msg} = "$name was deleted.";
    $c->response->redirect($c->uri_for('/person/search'));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->model('RetreatCenterDB::Person')->find($id);
    $c->stash->{person} = $p;
    #
    # ???can we make a 'relationship' between people and itself
    # and have $p->id_sps be another person object?
    # until then...
    #
    if (my $id_sps = $p->id_sps()) {
        my $sps = $c->model('RetreatCenterDB::Person')->find($id_sps);
        $c->stash->{partner} = $sps;
    }
    $c->stash->{sex} = ($p->sex() eq "M")? "Male": "Female";
    $c->stash->{affils} = [
        $p->affils(
            undef,
            {order_by => 'descrip'}
        )
    ];
    $c->stash->{date_entrd} = date($p->date_entrd()) || "";
    $c->stash->{date_updat} = date($p->date_updat()) || "";
    $c->stash->{date_hf}    = date($p->date_hf())    || "";;
    $c->stash->{date_lm}    = date($p->date_lm())    || "";;
    $c->stash->{date_path}  = date($p->date_path())  || "";;
    $c->stash->{template} = "person/view.tt2";
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->model('RetreatCenterDB::Person')->find($id);
    $c->stash->{person} = $p;
    my $sex = $p->sex();
    $c->stash->{sex_female}  = ($sex eq "F")? "checked": "";
    $c->stash->{sex_male}    = ($sex eq "M")? "checked": "";
    $c->stash->{affil_table} = affil_table($c, $p->affils());
    $c->stash->{date_hf}     = date($p->date_hf())   || "";
    $c->stash->{date_lm}     = date($p->date_lm())   || "";
    $c->stash->{date_path}   = date($p->date_path()) || "";
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "person/person.tt2";
}

#
# currently there's no way to know which fields changed
# so assume they all did.  DBIx::Class is smart about this.
# can we be smart about affils???  yes, see ZZ below.
#
# check for dups???
#
sub update_do : Local {
    my ($self, $c, $id) = @_;

    # dates are either blank or converted to d8 format
    my @mess;
    for my $d (qw/ date_hf date_lm date_path /) {
        my $fld = $c->request->params->{$d};
        my $dt = date($fld);
        if ($fld && ! $dt) {
            # tell them which date field is wrong???
            push @mess, "Invalid date: $fld";
            next;
        }
        $c->request->params->{$d} = $dt? $dt->as_d8()
                                   :     "";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "person/error.tt2";
        return;
    }

    my $p = $c->model("RetreatCenterDB::Person")->find($id);
    $p->update({
        last     => $c->request->params->{last},
        first    => $c->request->params->{first},
        sanskrit => $c->request->params->{sanskrit},
        sex      => $c->request->params->{sex},
        addr1    => $c->request->params->{addr1},
        addr2    => $c->request->params->{addr2},
        city     => $c->request->params->{city},
        st_prov  => $c->request->params->{st_prov},
        zip_post => $c->request->params->{zip_post},
        country  => $c->request->params->{country},
        email    => $c->request->params->{email},
        tel_home => $c->request->params->{tel_home},
        tel_work => $c->request->params->{tel_work},
        tel_cell => $c->request->params->{tel_cell},
        comment  => $c->request->params->{comment},
        date_hf    => $c->request->params->{date_hf},
        date_lm    => $c->request->params->{date_lm},
        date_path  => $c->request->params->{date_path},
        date_updat => today()->as_d8(),
    });
    #
    # which affiliations are checked now?
    #
    my @cur_affils = grep { s/^aff(\d+)/$1/ }
                     keys %{$c->request->params};
    # delete all old affiliations and create the new ones.
    # ZZ - later - remember old, if no new do nothing... yes.
    # if anything changed - just redo all by deleting/adding.
    # trying to be smarter than this is probably not worth it?
    $c->model("RetreatCenterDB::AffilPerson")->search(
        { p_id => $id },
    )->delete();
    for my $ca (@cur_affils) {
        $c->model("RetreatCenterDB::AffilPerson")->create({
            a_id => $ca,
            p_id => $id,
        });
    }

    $c->flash->{status_msg} = $p->first() . " " . $p->last() . " was updated.";
    $c->response->redirect($c->uri_for('/person/search'));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{affil_table} = affil_table($c);
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "person/person.tt2";
}

#
# check for dups???
#
sub create_do : Local {
    my ($self, $c) = @_;

    # dates are either blank or converted to d8 format
    my @mess;
    for my $d (qw/ date_hf date_lm date_path /) {
        my $fld = $c->request->params->{$d};
        my $dt = date($fld);
        if ($fld && ! $dt) {
            # tell them which date field is wrong???
            push @mess, "Invalid date: $fld";
            next;
        }
        $c->request->params->{$d} = $dt? $dt->as_d8()
                                   :     "";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>n", @mess;
        $c->stash->{template} = "person/error.tt2";
        return;
    }

    my $p = $c->model("RetreatCenterDB::Person")->create({
        last     => $c->request->params->{last},
        first    => $c->request->params->{first},
        sanskrit => $c->request->params->{sanskrit},
        sex      => $c->request->params->{sex},
        addr1    => $c->request->params->{addr1},
        addr2    => $c->request->params->{addr2},
        city     => $c->request->params->{city},
        st_prov  => $c->request->params->{st_prov},
        zip_post => $c->request->params->{zip_post},
        country  => $c->request->params->{country},
        email    => $c->request->params->{email},
        tel_home => $c->request->params->{tel_home},
        tel_work => $c->request->params->{tel_work},
        tel_cell => $c->request->params->{tel_cell},
        comment  => $c->request->params->{comment},
        date_hf    => $c->request->params->{date_hf},
        date_lm    => $c->request->params->{date_lm},
        date_path  => $c->request->params->{date_path},
        date_updat => today()->as_d8(),
        date_entrd => today()->as_d8(),
    });
    my $id = $p->id();
    #
    # which affiliations are checked?
    #
    my @cur_affils = grep { s/^aff(\d+)/$1/ }
                     keys %{$c->request->params};
    for my $ca (@cur_affils) {
        $c->model("RetreatCenterDB::AffilPerson")->create({
            a_id => $ca,
            p_id => $id,
        });
    }
    $c->stash->{message} = "Created";
    $c->stash->{template} = "person/search.tt2";
}

sub separate : Local {
    my ($self, $c, $id) = @_;
    my $p   = $c->model('RetreatCenterDB::Person')->find($id);
    my $sps = $c->model('RetreatCenterDB::Person')->find($p->id_sps());
    $p->update({
        id_sps => 0,
    });
    $sps->update({
        id_sps => 0,
    });
    view($self, $c, $id);
    # how about rewriting the url?
    # use forward instead?
}

1;
