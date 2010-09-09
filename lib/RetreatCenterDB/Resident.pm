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

__PACKAGE__->belongs_to('person' => 'RetreatCenterDB::Person', 'person_id');

1;
