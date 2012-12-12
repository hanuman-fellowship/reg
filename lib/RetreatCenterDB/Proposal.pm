use strict;
use warnings;
package RetreatCenterDB::Proposal;
use base qw/DBIx::Class/;
use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;
use Util qw/
    expand
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('proposal');
__PACKAGE__->add_columns(qw/
    id
    date_of_call
    group_name
    rental_type
    max
    min
    dates_requested
    checkin_time
    checkout_time
    other_things
    meeting_space
    housing_space
    leader_housing
    special_needs
    food_service
    other_requests
    program_meeting_date
    denied
    provisos

    first
    last
    addr1
    addr2
    city
    st_prov
    zip_post
    country
    tel_home
    tel_work
    tel_cell
    email

    cs_first
    cs_last
    cs_addr1
    cs_addr2
    cs_city
    cs_st_prov
    cs_zip_post
    cs_country
    cs_tel_home
    cs_tel_work
    cs_tel_cell
    cs_email

    deposit
    misc_notes
    rental_id
    person_id
    cs_person_id
    staff_ok
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(rental  => 'RetreatCenterDB::Rental',  'rental_id');
__PACKAGE__->belongs_to(person  => 'RetreatCenterDB::Person',  'person_id');
__PACKAGE__->belongs_to(cs_person => 'RetreatCenterDB::Person', 'cs_person_id');

sub date_of_call_obj  { date(shift->date_of_call) || ""; }
sub program_meeting_date_obj { date(shift->program_meeting_date) || ""; }

sub checkin_time_obj  { get_time(shift->checkin_time());  }
sub checkout_time_obj { get_time(shift->checkout_time()); }

sub dates_requested_ex  { expand(shift->dates_requested()); }
sub special_needs_ex    { expand(shift->special_needs  ()); }
sub food_service_ex     { expand(shift->food_service   ()); }
sub other_requests_ex   { expand(shift->other_requests ()); }
sub provisos_ex         { expand(shift->provisos       ()); }
sub misc_notes_ex       { expand(shift->misc_notes     ()); }

sub status {
    my ($self) = @_;
    
    if ($self->denied) {
        return "Denied";
    }
    elsif ($self->rental_id) {
        return "Accepted";
    }
    else {
        return "New";
    }
}

1;
__END__
addr1 - 
addr2 - 
checkin_time - 
checkout_time - 
city - 
country - 
cs_addr1 - 
cs_addr2 - 
cs_city - 
cs_country - 
cs_email - 
cs_first - 
cs_last - 
cs_person_id - foreign key to person
cs_st_prov - 
cs_tel_cell - 
cs_tel_home - 
cs_tel_work - 
cs_zip_post - 
date_of_call - 
dates_requested - 
denied - 
deposit - 
email - 
first - 
food_service - 
group_name - 
housing_space - 
id - unique id
last - 
leader_housing - 
max - 
meeting_space - 
min - 
misc_notes - 
other_requests - 
other_things - 
person_id - foreign key to person
program_meeting_date - 
provisos - 
rental_id - foreign key to rental
rental_type - 
special_needs - 
st_prov - 
staff_ok - 
tel_cell - 
tel_home - 
tel_work - 
zip_post - 
