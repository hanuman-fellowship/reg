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
overview - When people call to ask about renting the space at MMC 
    a Proposal is created.  Information is gathered and the proposal
    is considered at the next Program admin meeting.   Creating a proposal
    awkwardly creates People records.
    <p>
    If a proposal is approved there is an Approved link on the proposal
    screen that creates a Rental from the Proposal - copying the information
    from the proposal to the rental.
addr1 - coordinator address 1
addr2 - coordinator address 2
checkin_time - when will they check in?  default 4:00 pm
checkout_time - when will they check out?  default 1:00 pm
city - coordinator city
country - coordinator country
cs_addr1 - contract signer address 1
cs_addr2 - contract signer address 2
cs_city - contract signer city
cs_country - contract signer country
cs_email - contract signer email address
cs_first - contract signer first name
cs_last - contract signer last name
cs_person_id - foreign key to person
cs_st_prov - contract signer state/province
cs_tel_cell - contract signer cell phone
cs_tel_home - contract signer home phone
cs_tel_work - contract signer work phone
cs_zip_post - contract signer zip/postal code
date_of_call - when did the call come in?
dates_requested - a free text field describing dates and/or date ranges
denied - was the proposal was denied?
deposit - the required deposit
email - coordinator email address
first - coordinator first name
food_service - free text describing food needs
group_name - name of the group requesting the rental
housing_space - what housing is needed?
id - unique id
last - coordinator last name
leader_housing - where will the leader be housed?
max - maximum # of people to be housed.  this number is used
    to calculate the contractual financial obligation.
meeting_space - what kind of meeting space is needed?
min - minimum # of people to be housed.
misc_notes - free text of other notes
other_requests - free text describing other requests
other_things - free text describing miscellaneous other things
person_id - foreign key to person
program_meeting_date - when will this proposal be considered? 
provisos - free text describing any provisos
rental_id - foreign key to rental
rental_type - what type of organization is requesting the rental?
    like psychology, yoga, sound healing, social justice, movement, etc.
special_needs - free text describing any special needs
st_prov - coordinator state/province
staff_ok - did the staff okay this proposal?
tel_cell - coordinator cell phone
tel_home - coordinator home phone
tel_work - coordinator work phone
zip_post - coordinator zip/postal code
