use strict;
use warnings;
package RetreatCenterDB::Resident;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('resident');
__PACKAGE__->add_columns(qw/
    id
    person_id
    comment
    image
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(person => 'RetreatCenterDB::Person', 'person_id');
__PACKAGE__->has_many(notes => 'RetreatCenterDB::ResidentNote', 'resident_id',
                      { order_by => 'the_date desc, the_time desc' });

sub category {
    my ($self) = @_;
    return $self->comment();
}

1;
__END__
overview - 
comment - 
id - unique id
image - 
person_id - foreign key to person
