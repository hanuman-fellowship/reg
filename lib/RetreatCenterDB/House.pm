use strict;
use warnings;
package RetreatCenterDB::House;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('house');
__PACKAGE__->add_columns(qw/
    id
    name
    max
    bath
    tent
    center
    cabin
    priority
    x
    y
    cluster_id
    cluster_order
    inactive
    disp_code
    comment
    resident
    cat_abode
    sq_foot
    key_card
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(cluster => 'RetreatCenterDB::Cluster', 'cluster_id');

sub name_disp {
    my ($self) = @_;
    my $name = $self->name();
    $name =~ s{(\d{3})[BH]+$}{$1};
    $name;
}

1;
__END__
overview - Each room and tent site has a House record.
    The name is a misnomer because there are usually more than
    one room in a house.
bath - does the room have a bathroom?
cabin - is it a test cabin structure?
cat_abode - are cats allowed?
center - center tent?
cluster_id - foreign key to cluster
cluster_order - where should this house be displayed in the ClusterView?
comment - a longer description of the space
disp_code - A above, B below, L left, or R right with an optional t to truncate name
id - unique id
inactive - no longer habitable?
key_card - does the door require an electronic key card?
max - how many beds?
name - short name of the space
priority - a number from 1 to 10 indicating how desirable the space is (1 is the most desirable).
resident - is this Resident housing?
sq_foot - room square footage - for resident housing
tent - is it a tent?
x - X coordinate for the DailyPic image
y - Y coordinate for the DailyPic image
