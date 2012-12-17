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
overview - 
date_needed - 
date_vacated - 
house_id - foreign key to house
refresh - 
