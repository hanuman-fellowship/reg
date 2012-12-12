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
cur - 
curmax - 
house_id - foreign key to house
program_id - foreign key to program
rental_id - foreign key to rental
sex - 
the_date - 
