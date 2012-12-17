use strict;
use warnings;
package RetreatCenterDB::MakeUp;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('make_up');
__PACKAGE__->add_columns(qw/
    house_id
    date_vacated
    date_needed
    refresh
/);
__PACKAGE__->set_primary_key(qw/house_id/);

__PACKAGE__->belongs_to(house => 'RetreatCenterDB::House', 'house_id');

sub date_vacated_obj {
    my ($self) = @_;
    return date($self->date_vacated);
}
sub date_needed_obj {
    my ($self) = @_;
    return date($self->date_needed);
}

1;
__END__
overview - Records indicating which rooms/tent sites need to be cleaned/made-up.
    And by when.
date_needed - When is the space next needed?
date_vacated - When was the space vacated?
house_id - foreign key to house
refresh - Does this space need to be refreshed now?  This is for programs/rentals
    that are longer than a week - the beds need fresh linen periodically.
