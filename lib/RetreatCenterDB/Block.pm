use strict;
use warnings;
package RetreatCenterDB::Block;
use base qw/DBIx::Class/;

use Util qw/
    ptrim
/;
use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('block');
__PACKAGE__->add_columns(qw/
    id
    house_id
    sdate
    edate
    nbeds
    npeople
    reason
    comment
    allocated
    user_id
    the_date
    time
    rental_id
    program_id
    event_id
/);
__PACKAGE__->set_primary_key(qw/
    id
/);

__PACKAGE__->belongs_to('house'   => 'RetreatCenterDB::House', 'house_id');
__PACKAGE__->belongs_to('user'    => 'RetreatCenterDB::User',  'user_id');

__PACKAGE__->belongs_to('event'   => 'RetreatCenterDB::Event',   'event_id');
__PACKAGE__->belongs_to('program' => 'RetreatCenterDB::Program', 'program_id');
__PACKAGE__->belongs_to('rental'  => 'RetreatCenterDB::Rental',  'rental_id');

sub sdate_obj {
    my ($self) = @_;
    return date($self->sdate()) || "";
}
sub edate_obj {
    my ($self) = @_;
    return date($self->edate()) || "";
}
sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date()) || "";
}
sub time_obj {
    my ($self) = @_;
    return get_time($self->time()) || "";
}
sub comment_tr {
    my ($self) = @_;
    return ptrim($self->comment());
}

1;
__END__
allocated - 
comment - 
edate - 
event_id - foreign key to event
house_id - foreign key to house
id - unique id
nbeds - 
npeople - 
program_id - foreign key to program
reason - 
rental_id - foreign key to rental
sdate - 
the_date - 
time - 
user_id - foreign key to user
