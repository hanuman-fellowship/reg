use strict;
use warnings;
package RetreatCenterDB::AffilReport;
use base qw/DBIx::Class/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('affil_reports');
# Set columns in table
__PACKAGE__->add_columns(qw/
    affiliation_id
    report_id
/);
#
# Set relationships:
#
__PACKAGE__->belongs_to(report => 'RetreatCenterDB::Report', 'report_id');
__PACKAGE__->belongs_to(affil  => 'RetreatCenterDB::Affil',  'affiliation_id');


1;
