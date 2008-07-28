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
