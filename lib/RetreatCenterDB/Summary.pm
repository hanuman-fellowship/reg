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
    leader_arrival
    leader_departure
    leader_housing
    food_service
    flowers
    lodging
    special_needs
    finances
    staff_arrival
    miscellaneous
    feedback
    field_staff_setup
    sound_setup
    school_spaces
    vacate_early
    need_books
    participant_list
    schedule
    yoga_classes
    work_study
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('who'   => 'RetreatCenterDB::User',    'who_updated');
__PACKAGE__->might_have(rental  => 'RetreatCenterDB::Rental',  'summary_id');
__PACKAGE__->might_have(program => 'RetreatCenterDB::Program', 'summary_id');

sub     date_updated_obj { date(shift->date_updated) || ""; }
sub     time_updated_obj { get_time(shift->time_updated); }

sub flowers_tr           { ptrim(shift->flowers()          ) };
sub field_staff_setup_tr { ptrim(shift->field_staff_setup()) };
sub food_service_tr      { ptrim(shift->food_service()     ) };

# ??? no longer needed?
sub    leader_housing_ex { expand(shift->leader_housing   ()); }
sub           signage_ex { expand(shift->signage          ()); }
sub     miscellaneous_ex { expand(shift->miscellaneous    ()); }
sub          feedback_ex { expand(shift->feedback         ()); }
sub      food_service_ex { expand(shift->food_service     ()); }
sub           flowers_ex { expand(shift->flowers          ()); }
sub           lodging_ex { expand(shift->lodging          ()); }
sub     special_needs_ex { expand(shift->special_needs    ()); }
sub          finances_ex { expand(shift->finances         ()); }
sub field_staff_setup_ex { expand(shift->field_staff_setup()); }
sub       sound_setup_ex { expand(shift->sound_setup      ()); }

1;
