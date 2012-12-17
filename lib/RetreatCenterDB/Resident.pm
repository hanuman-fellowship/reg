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
overview - People can become residents of MMC by registering (or being "enrolled"
    by someone authorized to do so) for a program with a Category of YSC, YSL, Intern, etc.
    They are then assigned resident housing.
comment - free text
id - unique id
image - is there a picture?   a naming convention finds the file.
person_id - foreign key to person
