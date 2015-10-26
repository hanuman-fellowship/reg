use strict;
use warnings;
package RetreatCenterDB::Level;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('level');
__PACKAGE__->add_columns(qw/
    id
    name
    long_term
    public
    school_id
    name_regex
    glnum_suffix
/);
__PACKAGE__->set_primary_key(qw/id/);

# school
__PACKAGE__->belongs_to(school => 'RetreatCenterDB::School',
                        'school_id');
1;
__END__
overview - A type of program.  
id - unique id
glnum_suffix - digits 2-6 of the general ledger number of payments
    for programs with this level.
long_term - Does this program span many months?
    If so registrants can be imported from it as well.
    Also it will not appear on the calendar.
name - the level name: Course, Public Course,
    AHC, YTT 200S, CS YSC1 etc.
    Diploma and Certificate are for older programs only.
name_regex - a regular expression that must match the program's name
public - Will this course stand alone and be offered to the general public?
school_id - foreign key to School - optional - could be 0
