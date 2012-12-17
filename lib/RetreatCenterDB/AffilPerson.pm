use strict;
use warnings;
package RetreatCenterDB::AffilPerson;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('affil_people');
__PACKAGE__->add_columns(qw/
    a_id
    p_id
/);
__PACKAGE__->set_primary_key(qw/
    a_id
    p_id
/);

#
# Set relationships:
#
__PACKAGE__->belongs_to(person => 'RetreatCenterDB::Person', 'p_id');
__PACKAGE__->belongs_to(affil  => 'RetreatCenterDB::Affil',  'a_id');


1;
__END__
overview - A mapping table between affiliations and persons.
a_id - foreign key to affil
p_id - foreign key to person
