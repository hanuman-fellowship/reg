package RetreatCenter::Controller::Affiliations;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

RetreatCenter::Controller::Affiliations - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->response->body('Matched RetreatCenter::Controller::Affiliations in Affiliations.');
}


=head1 AUTHOR

Shanker Neelakantan

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
