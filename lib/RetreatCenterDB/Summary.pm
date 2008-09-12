use strict;
use warnings;
package RetreatCenterDB::Summary;
use base qw/DBIx::Class/;
use Date::Simple qw/
    date
/;
use Util qw/
    _br
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

# AUTOLOAD???  already used?
sub     date_updated_obj { date(shift->date_updated) || ""; }
sub           signage_br { _br(shift->signage          ()); }
sub     miscellaneous_br { _br(shift->miscellaneous    ()); }
sub          feedback_br { _br(shift->feedback         ()); }
sub      food_service_br { _br(shift->food_service     ()); }
sub           flowers_br { _br(shift->flowers          ()); }
sub           lodging_br { _br(shift->lodging          ()); }
sub     special_needs_br { _br(shift->special_needs    ()); }
sub          finances_br { _br(shift->finances         ()); }
sub field_staff_setup_br { _br(shift->field_staff_setup()); }
sub       sound_setup_br { _br(shift->sound_setup      ()); }

1;
