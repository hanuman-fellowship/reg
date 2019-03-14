use strict;
use warnings;
package RetreatCenterDB::Activity;
use base qw/RetreatCenterDB::Result/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('activity');
# Set columns in table
__PACKAGE__->add_columns(
    id => { data_type => 'integer', is_auto_increment => 1 },
    message => { data_type => 'varchar', size => 256 },
    cdate => { data_type => 'varchar', size => 8, date_simple => 1 },
    ctime => { data_type => 'varchar', size => 4, time_simple => 1 },
);

# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);
__PACKAGE__->resultset_class('RetreatCenterDB::ResultSet::Activity');

1;
__END__
overview - Activity log imported into Reg from external (populated by the grab_new process).
id - Primary key
message - A human description of the external activity
cdate - Creation date
ctime - Creation time
