use strict;
use warnings;
package RetreatCenterDB::Affil;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('affils');
__PACKAGE__->add_columns(qw/
    id
    descrip
    system
    selectable
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(affil_person => 'RetreatCenterDB::AffilPerson', 'a_id');
__PACKAGE__->many_to_many(people => 'affil_person', 'person');

__PACKAGE__->has_many(affil_program => 'RetreatCenterDB::AffilProgram', 'a_id');
__PACKAGE__->many_to_many(programs => 'affil_program', 'program');

__PACKAGE__->has_many(affil_report => 'RetreatCenterDB::AffilReport',
                      'affiliation_id');
__PACKAGE__->many_to_many(reports => 'affil_report', 'report');

1;
__END__
overview - Affiliations are used to describe a person's interests -
    the way that they are connected to the center.   Programs have affiliations
    that are assigned to everyone registering for the program.  Reports 
    search for everyone that has an affiliation.
descrip - the description of the affiliation
id - unique id
selectable - a boolean.  is the system affiliation selectable when editing
    a person or program?
system - a boolean.  if 'yes' it means Reg uses this affiliation internally.
    Cannot be edited.
