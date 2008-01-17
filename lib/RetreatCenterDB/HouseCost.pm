use strict;
use warnings;
package RetreatCenterDB::HouseCost;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('housecost');
__PACKAGE__->add_columns(qw/
    id
    name
    single
    double
    triple
    quad
    dormitory
    economy
    center_tent
    own_tent
    own_van
    commuting
    unknown
    single_bath
    double_bath
    type
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(programs => 'RetreatCenterDB::Program', 'housecost_id', 
                      { order_by => 'name' });

1;
