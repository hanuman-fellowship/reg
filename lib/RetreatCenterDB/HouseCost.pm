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
    dormitory
    economy
    center_tent
    own_tent
    own_van
    commuting
    single_bath
    dble_bath
    type
    inactive
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(programs => 'RetreatCenterDB::Program', 'housecost_id', 
                      { order_by => 'sdate desc' });
__PACKAGE__->has_many(rentals => 'RetreatCenterDB::Rental', 'housecost_id', 
                      { order_by => 'sdate desc' });

sub unknown    { my ($self) = @_; return 0; }
sub not_needed { my ($self) = @_; return 0; }

1;
__END__
overview - 
center_tent - 
commuting - 
dble - 
dble_bath - 
dormitory - 
economy - 
id - unique id
inactive - 
name - 
own_tent - 
own_van - 
single - 
single_bath - 
triple - 
type - 
