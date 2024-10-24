use strict;
use warnings;
package RetreatCenter::Controller::Resident;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    trim
    valid_email
    model
    stash
    read_only
/;
use Date::Simple qw/
    today
/;
use Time::Simple qw/
    get_time
/;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    my @residents = ();
    for my $r (
        sort {
            $a->person->last()  cmp $b->person->last()
            or
            $a->person->first() cmp $b->person->first()
        }
        model($c, 'Resident')->all()
    ) {
        # what category?
        # current reg in resident program - yes
        # past reg in resident program - ???
        # no reg in a resident program - ???
        #
        my $cat = 'Not Yet';
        my $reg_id = 0;
        my $today = today()->as_d8();
        REG:
        for my $reg (sort {
                         $b->program->sdate() <=> $a->program->sdate()
                     }
                     $r->person->registrations()
        ) {
            my $pcat = $reg->program->category->name();
            next REG if $pcat eq 'Normal';
            $cat = $pcat;
            $reg_id = $reg->id();
            if ($reg->program->edate() <= $today) {
                $cat .= " - " . $reg->program->edate_obj->format("%b '%y");
            }
            last REG;
        }
        push @residents, {
            id        => $r->id(),
            person_id => $r->person->id(),
            first     => $r->person->first(),
            last      => $r->person->last(),
            category  => $cat,
            reg_id    => $reg_id,
        };
    }
    stash($c,
        residents => \@residents,
        template  => "resident/list.tt2",
    );
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
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
    model($c, 'ResidentNote')->search({resident_id => $id})->delete();
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

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
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
    model($c, 'Resident')->find($id)->update({
        %hash,
    });
    $c->response->redirect($c->uri_for("/resident/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    stash($c,
        resident => model($c, 'Resident')->find($id),
        template => 'resident/view.tt2',
    );
}

sub create : Local {
    my ($self, $c, $person_id) = @_;

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    stash($c,
        person      => model($c, 'Person')->find($person_id),
        form_action => "create_do/$person_id",
        template    => 'resident/create_edit.tt2',
    );
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
    $c->response->redirect($c->uri_for("/resident/view/$id"));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

sub note : Local {
    my ($self, $c, $id) = @_;

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    stash($c,
        resident => model($c, 'Resident')->find($id),
        template => 'resident/note.tt2',
    );
}

sub note_do : Local {
    my ($self, $c, $id) = @_;

    model($c, 'ResidentNote')->create({
        resident_id => $id,
        the_date    => today->as_d8(),
        the_time    => get_time()->t24(),
        note        => $c->request->params->{note},
    });
    $c->response->redirect($c->uri_for("/resident/view/$id"));
}

1;
