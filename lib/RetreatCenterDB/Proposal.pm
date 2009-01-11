use strict;
use warnings;
package RetreatCenterDB::Proposal;
use base qw/DBIx::Class/;
use Date::Simple qw/
    date
/;
use Util qw/
    _br
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
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(rental  => 'RetreatCenterDB::Rental',  'rental_id');
__PACKAGE__->belongs_to(person  => 'RetreatCenterDB::Person',  'person_id');
__PACKAGE__->belongs_to(cs_person => 'RetreatCenterDB::Person', 'cs_person_id');

sub date_of_call_obj  { date(shift->date_of_call) || ""; }
sub program_meeting_date_obj { date(shift->program_meeting_date) || ""; }
sub dates_requested_br  { _br(shift->dates_requested()); }
sub special_needs_br    { _br(shift->special_needs  ()); }
sub food_service_br     { _br(shift->food_service   ()); }
sub other_requests_br   { _br(shift->other_requests ()); }
sub provisos_br         { _br(shift->provisos       ()); }
sub misc_notes_br       { _br(shift->misc_notes     ()); }

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
