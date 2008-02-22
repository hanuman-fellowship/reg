use strict;
use warnings;
package RetreatCenterDB::Leader;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('leader');
__PACKAGE__->add_columns(qw/
    id
    person_id
    public_email
    url
    image
    biography
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(leader_program => 'RetreatCenterDB::LeaderProgram',
                      'l_id');
__PACKAGE__->many_to_many(programs => 'leader_program', 'program',
                          { order_by => 'sdate desc' });
__PACKAGE__->belongs_to('person' => 'RetreatCenterDB::Person', 'person_id');

sub biography_br {
    my ($self) = @_;
    my $biography = $self->biography;
    $biography =~ s{\r?\n}{<br>\n}g;
    $biography;
}

1;
