use strict;
use warnings;
package RetreatCenterDB::HousingType;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('housing_type');
__PACKAGE__->add_columns(qw/
    name
    ht_order
    short_desc
    long_desc
/);
__PACKAGE__->set_primary_key(qw/name/);

1;
__END__
overview - Housing types - from 'own tent' to 'whole cottage'
ht_order - what order to present the housing types in
long_desc - a long (however long you wish) description
name - brief internal name of the type
short_desc - a short succinct description
