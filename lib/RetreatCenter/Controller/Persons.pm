package RetreatCenter::Controller::Persons;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

RetreatCenter::Controller::Persons - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->response->body('Matched RetreatCenter::Controller::Persons in Persons.');
}

sub list : Local {
    my ($self, $c) = @_;

    # Retrieve all of the book records as book model objects and store in the
    # stash where they can be accessed by the TT template
    $c->stash->{persons} = [$c->model('RetreatCenterDB::Person')->all];
    
    # Set the TT template to use.  You will almost always want to do this
    # in your action methods (action methods respond to user input in
    # your controllers).
    $c->stash->{template} = 'persons/list.tt2';
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{form_action} = 'create_do';
    $c->stash->{template} = 'persons/edit.tt2';
}

sub create_do : Local {
    my ($self, $c) = @_;

    my $first = $c->request->params->{first};
    my $last = $c->request->params->{last};
    my $addr = $c->request->params->{address};
    my $city = $c->request->params->{city};
    my $state = $c->request->params->{state};
    my $zip = $c->request->params->{zip};
    my $email = $c->request->params->{email};

    my $person = $c->model('RetreatCenterDB::Person')->create({
        first_name => $first,
        last_name  => $last,
        address    => $addr,
        city       => $city,
        state      => $state,
        zip        => $zip,
        email      => $email,
    });
    $c->forward('list');
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    my $person_rs = $c->model('RetreatCenterDB::Person')->search(id => $id);

    my $person = $person_rs->find($id);

    if ($person_rs->delete) {
        $c->stash->{status_msg} = 'Person ' . $person->first_name . " " . $person->last_name . ' deleted';
    }
    $c->forward('list');
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $person_rs = $c->model('RetreatCenterDB::Person')->search(id => $id);

    my $person = $person_rs->find($id);

    $c->stash->{person} = $person;
    $c->stash->{form_action} = "update_do/$id";

    $c->stash->{template} = 'persons/edit.tt2';
}

sub update_do  {
    my ($self, $c, $id) = @_;

    my $person_rs = $c->model('RetreatCenterDB::Person')->search(id => $id);
    my $person = $person_rs->find($id);

    my $first = $c->request->params->{first};
    my $last = $c->request->params->{last};
    my $addr = $c->request->params->{address};
    my $city = $c->request->params->{city};
    my $state = $c->request->params->{state};
    my $zip = $c->request->params->{zip};
    my $email = $c->request->params->{email};

    $person_rs->update({
        first_name => $first,
        last_name  => $last,
        address    => $addr,
        city       => $city,
        state      => $state,
        zip        => $zip,
        email      => $email,
    });

    $c->forward('list');
}

sub search : Local {
    my ($self, $c) = @_;

    $c->stash->{template} = 'persons/search.tt2';
}

sub search_do : Local {
    my ($self, $c) = @_;

    my $prefix = $c->request->params->{prefix};

    #my @persons = $c->model('RetreatCenterDB::Person')->resultset('Person')->search(
    my @persons = $c->model('RetreatCenterDB::Person')->search(
        { last_name => { 'like', "$prefix%" } },
    );
    use Data::Dumper;
    $Data::Dumper::Useperl = 1;
    $c->stash->{data} = Dumper(\@persons);
    $c->stash->{persons} = \@persons;
    
    $c->stash->{template} = 'persons/list.tt2';
}


=head1 AUTHOR

Shanker Neelakantan

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
