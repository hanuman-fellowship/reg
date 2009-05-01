use strict;
use warnings;
package RetreatCenterDB::Summary;
use base qw/DBIx::Class/;
use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;
use Util qw/
    expand
    ptrim
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('summary');
__PACKAGE__->add_columns(qw/
    id
    date_updated
    time_updated
    who_updated
    gate_code
    registration_location
    signage
    orientation
    wind_up
    alongside
    back_to_back
    leader_name
    staff_arrival
    staff_departure
    leader_housing
    food_service
    flowers
    miscellaneous
    feedback
    field_staff_setup
    sound_setup
    check_list
    converted_spaces
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('who'   => 'RetreatCenterDB::User',    'who_updated');
__PACKAGE__->might_have(rental  => 'RetreatCenterDB::Rental',  'summary_id');
__PACKAGE__->might_have(program => 'RetreatCenterDB::Program', 'summary_id');

sub     date_updated_obj { date(shift->date_updated) || ""; }
sub     time_updated_obj { get_time(shift->time_updated); }

sub leader_housing_tr    { ptrim(shift->leader_housing()   ) };
sub flowers_tr           { ptrim(shift->flowers()          ) };
sub signage_tr           { ptrim(shift->signage()          ) };
sub field_staff_setup_tr { ptrim(shift->field_staff_setup()) };
sub food_service_tr      { ptrim(shift->food_service()     ) };
sub sound_setup_tr       { ptrim(shift->sound_setup()      ) };

1;
