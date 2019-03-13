package RetreatCenterDB::ResultSet;

use strict;
use warnings;
use base 'DBIx::Class::ResultSet';

__PACKAGE__->load_components(qw//);

sub to_array {
  my ($self) = @_;
  return $self->search(
      {},
      {result_class => 'DBIx::Class::ResultClass::HashRefInflator'}
  )->all;
}

1;

