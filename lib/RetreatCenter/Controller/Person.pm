use strict;
use warnings;
package RetreatCenter::Controller::Person;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/affil_table trim nsquish/;
use Date::Simple qw/date today/;
use USState;

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

    my %order_by = (
        sanskrit => [ 'sanskrit', 'last', 'first' ],
        zip_post => [ 'zip_post', 'last', 'first' ],
        last     => [ 'last', 'first' ],
        
    );
    $c->stash->{people} = [
        $c->model('RetreatCenterDB::Person')->search(
            {
                $field => { 'like', "$substr$pattern%" },
            },
            {
                order_by => $order_by{$field},
                rows     => $nrecs,
            },
        )
    ];
    if (scalar(@{$c->stash->{people}}) == 0) {
        $c->stash->{message}  = "No one found matching '$pattern'.";
        $c->stash->{template} = "person/search.tt2";
        return;
    }
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
    # and the partner id in case they're partnered.
    my $p = $c->model('RetreatCenterDB::Person')->find($id);
    my $name = $p->first() . " " . $p->last();
    my $id_sps = $p->id_sps();

    # now delete
    $c->model('RetreatCenterDB::Person')->search(
        { id => $id }
    )->delete();
    $c->model('RetreatCenterDB::AffilPerson')->search(
        { p_id => $id }
    )->delete();

    # were they partnered?  not any more.
    if ($id_sps) {
        my $partner = $c->model('RetreatCenterDB::Person')->find($id_sps);
        $partner->update({
            id_sps => 0,
        });
    }

    $c->flash->{message} = "$name was deleted.";
    $c->response->redirect($c->uri_for('/person/search'));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->model('RetreatCenterDB::Person')->find($id);
    if (! $p) {
        $c->stash->{mess} = "Person not found - sorry.";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }
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
    $c->stash->{affils} = [ $p->affils() ];
    $c->stash->{date_entrd} = date($p->date_entrd()) || "";
    $c->stash->{date_updat} = date($p->date_updat()) || "";
    $c->stash->{date_hf}    = date($p->date_hf())    || "";;
    $c->stash->{date_lm}    = date($p->date_lm())    || "";;
    $c->stash->{date_path}  = date($p->date_path())  || "";;

    # is this person a leader?
    my @leads = $c->model('RetreatCenterDB::Leader')->search(
        { person_id => $id }
    );
    $c->stash->{is_leader} = scalar(@leads);
    $c->stash->{leader} = $leads[0];
    $c->stash->{template} = "person/view.tt2";
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->model('RetreatCenterDB::Person')->find($id);
    $c->stash->{person} = $p;
    my $sex = $p->sex();
    $c->stash->{sex_female}  = ($sex eq "F")? "checked": "";
    $c->stash->{sex_male}    = ($sex eq "M")? "checked": "";
    $c->stash->{mailings}    = ($p->mailings())? "checked": "";
    $c->stash->{affil_table} = affil_table($c, $p->affils());
    $c->stash->{date_hf}     = date($p->date_hf())   || "";
    $c->stash->{date_lm}     = date($p->date_lm())   || "";
    $c->stash->{date_path}   = date($p->date_path()) || "";
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "person/create_edit.tt2";
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

    my $last     = $c->request->params->{last};
    my $first    = $c->request->params->{first};
    my $sex      = $c->request->params->{sex};
    my $addr1    = $c->request->params->{addr1};
    my $addr2    = $c->request->params->{addr2};
    my $city     = $c->request->params->{city};
    my $zip_post = $c->request->params->{zip_post};
    my $st_prov  = $c->request->params->{st_prov};
    my $country  = $c->request->params->{country};
    my $akey     = nsquish($addr1, $addr2, $zip_post);

    if ($sex ne 'F' && $sex ne 'M') {
        push @mess, "You must specify Male or Female.";
    }

    if ($addr1 && usa($country) && ! valid_state($st_prov)) {
        push @mess, "Invalid state: $st_prov";
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
        sex      => $sex,
        addr1    => $addr1,
        addr2    => $addr2,
        city     => $city,
        st_prov  => $st_prov,
        zip_post => $zip_post,
        country  => $country,
        akey     => nsquish($addr1, $addr2, $zip_post),
        email    => $c->request->params->{email},
        tel_home => $c->request->params->{tel_home},
        tel_work => $c->request->params->{tel_work},
        tel_cell => $c->request->params->{tel_cell},
        comment  => $c->request->params->{comment},
        mailings => $c->request->params->{mailings},
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
    #
    # in case this person was partnered we must
    # update the partner's address and home phone as well.
    #
    my $id_sps = $p->id_sps;
    my $partner;
    if ($id_sps != 0) {
        $partner = $c->model("RetreatCenterDB::Person")->find($id_sps);
        $partner->update({
            addr1    => $addr1,
            addr2    => $addr2,
            city     => $c->request->params->{city},
            st_prov  => $c->request->params->{st_prov},
            zip_post => $zip_post,
            country  => $c->request->params->{country},
            akey     => nsquish($addr1, $addr2, $zip_post),
            tel_home => $c->request->params->{tel_home},
        });
    }

    my $msg = _view_person($p);
    my $pronoun = ($p->sex eq "M")? "his": "her";
    my $verb = "was";
    if ($id_sps) {
        $msg .= " and $pronoun partner "
              . _view_person($partner);
        $verb = "were"
    }
    $msg .= " $verb updated.";
    #
    # look for possible duplicates and give a warning.
    # I know it would be better to catch a possible duplicate and prevent
    # it from being created at all but that's more work.
    # Perhaps later.
    #
    my @dups = $c->model("RetreatCenterDB::Person")->search(
        {
            last  => $last,
            first => $first,
            id    => { "!=", $id },     # but not ourselves
        },
    );
    my $Clast  = substr($last, 0, 1);
    my $Cfirst = substr($first, 0, 1);
    push @dups, $c->model("RetreatCenterDB::Person")->search(
        {
            last  => { 'like' => "$Clast%"  },
            first => { 'like' => "$Cfirst%" },
            akey  => $akey,
            id    => { "!=", $id },     # but not ourselves
        }
    );
    my %seen;
    @dups = grep { !$seen{$_->id}++; } @dups;   # undup possible dup dups :)
    my $dups;
    for my $d (@dups) {
        $dups .= _view_person($d) . ", ";
    }
    if ($dups) {
        $dups =~ s{, $}{};     # final ', '
        my $pl = (@dups == 1)? "": "s";
        $dups = " - Possible duplicate$pl: $dups.";
    }
    $c->flash->{message} = $msg . $dups;
    $c->response->redirect($c->uri_for('/person/search'));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{mailings}    = "checked";
    $c->stash->{affil_table} = affil_table($c);
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "person/create_edit.tt2";
}

sub _view_person {
    my ($p) = @_;
    "<a href='/person/view/" . $p->id . "'>"
    . $p->first . " " . $p->last
    . "</a>";
}

#
#
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

    my $last     = $c->request->params->{last};
    my $first    = $c->request->params->{first};
    my $sex      = $c->request->params->{sex};
    my $addr1    = $c->request->params->{addr1};
    my $addr2    = $c->request->params->{addr2};
    my $city     = $c->request->params->{city};
    my $zip_post = $c->request->params->{zip_post};
    my $st_prov  = $c->request->params->{st_prov};
    my $country  = $c->request->params->{country};
    my $akey     = nsquish($addr1, $addr2, $zip_post);

    if ($sex ne 'F' && $sex ne 'M') {
        push @mess, "You must specify Male or Female.";
    }

    if ($addr1 && usa($country) && ! valid_state($st_prov)) {
        push @mess, "Invalid state: $st_prov";
    }

    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "person/error.tt2";
        return;
    }

    my $p = $c->model("RetreatCenterDB::Person")->create({
        last     => $c->request->params->{last},
        first    => $c->request->params->{first},
        sanskrit => $c->request->params->{sanskrit},
        sex      => $sex,
        addr1    => $addr1,
        addr2    => $addr2,
        city     => $city,
        st_prov  => $st_prov,
        zip_post => $zip_post,
        country  => $country,
        akey     => $akey,
        email    => $c->request->params->{email},
        tel_home => $c->request->params->{tel_home},
        tel_work => $c->request->params->{tel_work},
        tel_cell => $c->request->params->{tel_cell},
        comment  => $c->request->params->{comment},
        mailings => $c->request->params->{mailings},
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
    #
    # look for possible duplicates and give a warning.
    # I know it would be better to catch a possible duplicate and prevent
    # it from being created at all but that's more work.
    # Perhaps later.
    #
    my @dups = $c->model("RetreatCenterDB::Person")->search(
        {
            last  => $last,
            first => $first,
            id    => { "!=", $id },     # but not ourselves
        },
    );
    my $Clast  = substr($last, 0, 1);
    my $Cfirst = substr($first, 0, 1);
    push @dups, $c->model("RetreatCenterDB::Person")->search(
        {
            last  => { 'like' => "$Clast%"  },
            first => { 'like' => "$Cfirst%" },
            akey  => $akey,
            id    => { "!=", $id },     # but not ourselves
        }
    );
    my %seen;
    @dups = grep { !$seen{$_->id}++; } @dups;   # undup possible dup dups :)
    my $dups;
    for my $d (@dups) {
        $dups .= _view_person($d) . ", ";
    }
    if ($dups) {
        $dups =~ s{, $}{};     # final ', '
        my $pl = (@dups == 1)? "": "s";
        $dups = " - Possible duplicate$pl: $dups.";
    }
    $c->flash->{message} = "Created " . _view_person($p) . $dups;
    $c->response->redirect($c->uri_for('/person/search'));
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
    $c->forward('view');
}

sub partner : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->model('RetreatCenterDB::Person')->find($id);
    $c->stash->{person} = $p;
    $c->stash->{template} = "person/partner.tt2";
}

sub partner_with : Local {
    my ($self, $c, $id) = @_;

    my $p1 = $c->model('RetreatCenterDB::Person')->find($id);
    my $first = trim($c->request->params->{first});
    my $last  = trim($c->request->params->{last});
    my (@people) = $c->model('RetreatCenterDB::Person')->search(
        {
            first => $first,
            last  => $last,
        },
    );
    if (@people == 1) {
        my $p2 = $people[0];
        if ($p2->id_sps != 0) {
            $c->stash->{message} = $p2->first . " " . $p2->last
                                 . " is already partnered!";
            $c->forward('search');
        }
        else {
            $p1->update({
                id_sps => $p2->id,
            });
            # partner #2 with automatically gets partner #1's address.
            # if they don't live together they don't get
            # to be partnered - in the mlist sense anyway.
            # is this discriminatory?
            $p2->update({
                id_sps   => $p1->id,
                addr1    => $p1->addr1,
                addr2    => $p1->addr2,
                city     => $p1->city,
                st_prov  => $p1->st_prov,
                zip_post => $p1->zip_post,
                country  => $p1->country,
                tel_home => $p1->tel_home,
            });
            $c->stash->{message} = "Partnered"
                                 . " " . _view_person($p1)
                                 . " with"
                                 . " " . _view_person($p2)
                                 . ".";
        }
        $c->forward('search');
    }
    else {
        $c->stash->{message} = $first . " " . $last
                             . " was not found - create them?";
        $c->stash->{form_action} = "/person/mkpartner/"
                                  . $id . "/"
                                  . $first . "/"
                                  . $last;

        $c->stash->{template} = "yes_no.tt2";
        return;
    }
}

sub mkpartner : Local {
    my ($self, $c, $id, $first, $last) = @_;

    my $p1 = $c->model('RetreatCenterDB::Person')->find($id);
    if (! $c->request->params->{yes}) {
        $c->stash->{message} = "The partnering of "
                              . _view_person($p1)
                              . " was cancelled.";
        $c->forward("search");
        return;
    }
    my $addr1    = $p1->addr1;
    my $addr2    = $p1->addr2;
    my $zip_post = $p1->zip_post;

    my $sex2 = ($p1->sex eq "M")? "F": "M";   # usually, not always
    my $p2 = $c->model("RetreatCenterDB::Person")->create({
        last     => $last,
        first    => $first,
        sanskrit => '',
        sex      => $sex2,
        addr1    => $addr1,
        addr2    => $addr2,
        city     => $p1->city,
        st_prov  => $p1->st_prov,
        zip_post => $zip_post,
        country  => $p1->country,
        akey     => nsquish($addr1, $addr2, $zip_post),
        tel_home => $p1->tel_home,
        id_sps   => $p1->id,
        date_entrd => today()->as_d8(),
    });
    $p1->update({
        id_sps => $p2->id,
    });
    my $pronoun = ($sex2 eq 'M')? "him": "her";
    $c->stash->{message} = "Created"
                         . " " . _view_person($p2)
                         . " and partnered $pronoun with"
                         . " " . _view_person($p1)
                         . ".";
    $c->forward("search");
}

1;
