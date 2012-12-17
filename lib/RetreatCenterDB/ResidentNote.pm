use strict;
use warnings;
package RetreatCenterDB::ResidentNote;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('resident_note');
__PACKAGE__->add_columns(qw/
    id
    resident_id
    the_date
    the_time
    note
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(resident => 'RetreatCenterDB::Resident',
                        'resident_id');

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date);
}

sub the_time_obj {
    my ($self) = @_;
    get_time($self->the_time());
}

1;
__END__
overview - 
id - unique id
note - 
resident_id - foreign key to resident
the_date - 
the_time - 
