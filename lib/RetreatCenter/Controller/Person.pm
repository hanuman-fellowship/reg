package RetreatCenter::Controller::Person;

use strict;
use warnings;
use base 'Catalyst::Controller';

use Util qw/affil_table date_fmt slash_to_d8/;
use Date::Simple qw/d8 today/;

=head1 NAME

RetreatCenter::Controller::Person - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('search');
}

sub search : Local {
    my ($self, $c) = @_;

    $c->stash->{template} = "person/search.tt2";
}

sub search_do : Local {
    my ($self, $c) = @_;

    my $pattern = $c->request->params->{pattern};
    $pattern =~ s{^\s*|\s*$}{}g;        # trim leading/trailing blanks
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
    # i tried using delete_all to do the cascade to the affils for this person.
    # look at the DBIC_TRACE - it does it very inefficiently :(.
    # delete with find() does the same.  but not with search()???.
    #
    #$c->model('RetreatCenterDB::Person')->search({id => $id})->delete_all();
    #
    #$c->model('RetreatCenterDB::Person')->find($id)->delete();
    #
    $c->model('RetreatCenterDB::Person')->search({id => $id})->delete();
    $c->model('RetreatCenterDB::AffilPerson')->search({p_id => $id})->delete();
    # the code below rewrites the url in the address
    # bar but does not give a message... :(
    $c->response->redirect(
        $c->uri_for(
            '/person/search',
            { message => "Deleted" }
        )
    );
}

# put this in Util.pm???
sub _trim {
    my ($s) = @_;

    $s =~ s{^\s*|\s*$}{}g;
    $s;
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->model('RetreatCenterDB::Person')->find($id);
    $c->stash->{person} = $p;
    $c->stash->{sex} = ($p->sex() eq "M")? "Male": "Female";
    $c->stash->{affils} = [
        $p->affils(
            undef,
            {order_by => 'descrip'}
        )
    ];
    $c->stash->{date_entrd} = date_fmt($p->date_entrd());
    $c->stash->{date_updat} = date_fmt($p->date_updat());
    $c->stash->{date_path}  = date_fmt($p->date_path());
    $c->stash->{date_lm}    = date_fmt($p->date_lm());
    $c->stash->{date_hf}    = date_fmt($p->date_hf());
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
    $c->stash->{date_lm}     = date_fmt($p->date_lm());
    $c->stash->{date_path}   = date_fmt($p->date_path());
    $c->stash->{date_hf}     = date_fmt($p->date_hf());
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "person/person.tt2";
}

#
# currently there's no way to know which fields changed
# so assume they all did.  DBIx::Class is smart about this.
# we can also be smart about affils...
#
# check for dups???
#
sub update_do : Local {
    my ($self, $c, $id) = @_;

    my $lm   = slash_to_d8($c->request->params->{date_lm});
    my $hf   = slash_to_d8($c->request->params->{date_hf});
    my $path = slash_to_d8($c->request->params->{date_path});
    $c->model("RetreatCenterDB::Person")->find($id)->update({
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
        date_lm  => $lm,
        date_hf  => $hf,
        date_path => $path,
        date_updat => today()->as_d8(),
    });
    #
    # which affiliations are checked now?
    #
    my @cur_affils = grep { s/^aff(\d+)/$1/ }
                     keys %{$c->request->params};
    # delete all old affiliations and create the new ones
    # later - remember old, if no new do nothing... yes.
    # if anything changed - just redo all by deleting/adding.
    $c->model("RetreatCenterDB::AffilPerson")->search(
        { p_id => $id },
    )->delete();
    for my $ca (@cur_affils) {
        $c->model("RetreatCenterDB::AffilPerson")->create({
            a_id => $ca,
            p_id => $id,
        });
    }
    $c->stash->{message} = "Updated";
    $c->stash->{template} = "person/search.tt2";
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

    my $lm   = slash_to_d8($c->request->params->{date_lm});
    my $hf   = slash_to_d8($c->request->params->{date_hf});
    my $path = slash_to_d8($c->request->params->{date_path});
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
        date_lm  => $lm,
        date_hf  => $hf,
        date_path => $path,
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
=head1 AUTHOR

Jon Bjornstad

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
