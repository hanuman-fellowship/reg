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
    dble
    triple
    quad
    dormitory
    economy
    center_tent
    own_tent
    own_van
    commuting
    single_bath
    dble_bath
    type
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(programs => 'RetreatCenterDB::Program', 'housecost_id', 
                      { order_by => 'sdate desc' });
__PACKAGE__->has_many(rentals => 'RetreatCenterDB::Rental', 'housecost_id', 
                      { order_by => 'sdate desc' });

1;
