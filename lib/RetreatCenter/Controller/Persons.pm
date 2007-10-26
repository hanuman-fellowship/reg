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
    my ($self, $c) = @_;

    $c->response->body('Matched RetreatCenter::Controller::Persons in Persons.');
}


=head2 auto

=cut

sub auto : Private {
    my ($self, $c) = @_;

    if (defined($result = $c->form)) {
    }
}

=head1 AUTHOR

Shanker Neelakantan

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
