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
    assistant
    l_order
    just_first
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(leader_program => 'RetreatCenterDB::LeaderProgram',
                      'l_id');
__PACKAGE__->many_to_many(programs => 'leader_program', 'program',
                          { order_by => 'sdate desc' });
__PACKAGE__->belongs_to('person' => 'RetreatCenterDB::Person', 'person_id');

sub name_public_email {
    my ($self) = @_;
    my $person = $self->person();
    return $person->first() . " " . $person->last()
         . " <" . $self->public_email() . ">";
}
1;
__END__
assistant - 
biography - 
id - unique id
image - 
just_first - 
l_order - 
person_id - foreign key to person
public_email - 
url - 
