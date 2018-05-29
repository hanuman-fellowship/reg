use strict;
use warnings;
package RetreatCenterDB::Config;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('config');
__PACKAGE__->add_columns(qw/
    house_id
    the_date
    sex
    curmax
    cur
    program_id
    rental_id
/);
__PACKAGE__->set_primary_key(qw/
    house_id
    the_date
/);

__PACKAGE__->belongs_to(house   => 'RetreatCenterDB::House',   'house_id');
__PACKAGE__->belongs_to(program => 'RetreatCenterDB::Program', 'program_id');
__PACKAGE__->belongs_to(rental  => 'RetreatCenterDB::Rental',  'rental_id');

sub the_date_obj {
    my ($self) = @_;
    date($self->the_date) || "";
}

1;
__END__
overview - This is a critical table (somewhat misnamed) that
    keeps track of housing configuration.
    There is a record for each house (aka room/site) and each day
    out to a maximum date 4 years out.
    The sex attribute tells what gender is occupying the space.
    We must do our best to keep the different genders apart!
    The foreign keys to program and rental are filled in only if 
    a housing reservation came from such.
    Blocks and Meeting Space (sleeping too) reservations
    associated with an Event have no such foreign keys.
    config records are added periodically by the cronjob 'add_config'
    which is also called when a new house is added or its size changed.
cur - The # of people that are currently in this space.
curmax - Max capacity of the space.
house_id - foreign key to house
program_id - foreign key to program
rental_id - foreign key to rental
sex - U (As yet Undefined), M (Male), F (Female), X (Mixed), R (Rental), B (Block), S (meeting Space),
    or C (Unreported Gender).
the_date - The date.
