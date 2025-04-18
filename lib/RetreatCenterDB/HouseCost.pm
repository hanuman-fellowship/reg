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
overview - Rentals and Programs have a named house cost schedule.  This specifies
    a cost for each type of housing.  The type attribute says whether the cost
    is for each day or for the entire event.
center_tent - $ for center tents
commuting - $ for commuting
dble - $ for doubles
dble_bath - $ for doubles with bath
dormitory - $ for dormitories
economy - $ for economy housing
id - unique id
inactive - is it no longer to be used?
name - The name of the HouseCost
own_tent - $ for people bringing their own tent
own_van - $ for people sleeping in their vehicle
single - $ for singles
single_bath - $ for singles with bath
triple - $ for triples
type - Per Day or Total
