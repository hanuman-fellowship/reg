use strict;
use warnings;
package RetreatCenterDB::MealRequests;
use base qw/DBIx::Class/;


# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('meal_requests');
# Set columns in table
__PACKAGE__->add_columns(qw/
    id
    person_id
    date
    breakfast
    lunch
    dinner
    child
    date_requested
    time_requested
/);

# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

sub time_requested_obj {
    my ($self) = @_;
    return get_time($self->time_requested());
}

sub date_requested_obj {
    my ($self) = @_;
    return get_time($self->date_requested());
}

sub date_obj {
    my ($self) = @_;
    return get_time($self->date());
}

__PACKAGE__->belongs_to(person   => 'RetreatCenterDB::Person', 'person_id');

1;
__END__
overview - Online Meal Requests for breakfast, lunch and dinner 
id - Primary key
person_id - foreign key to Person
date - date of requested meals
breakfast - # of breakfasts
lunch - # of lunches
dinner - # of dinners
child - meal for a child instead of an adult?
date_requested - date request was made
time_requested - time request was made
