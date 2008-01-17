use strict;
use warnings;
package RetreatCenterDB::Affil;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('affils');
__PACKAGE__->add_columns(qw/
    id
    descrip
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(affil_person => 'RetreatCenterDB::AffilPerson', 'a_id');
__PACKAGE__->many_to_many(people => 'affil_person', 'person',
                          { order_by => ['last', 'first']});
__PACKAGE__->has_many(affil_program => 'RetreatCenterDB::AffilProgram', 'a_id');
__PACKAGE__->many_to_many(programs => 'affil_program', 'program',
                          { order_by => 'name'});
__PACKAGE__->has_many(affil_report => 'RetreatCenterDB::AffilReport', 'affiliation_id');
__PACKAGE__->many_to_many(reports => 'affil_report', 'report',
                          { order_by => 'descrip'});

1;
