use strict;
use warnings;
package RetreatCenterDB::Activity;
use base qw/DBIx::Class/;

use Time::Simple qw/
    get_time
/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('activity');
# Set columns in table
__PACKAGE__->add_columns(qw/
    id
    message
    cdate
    ctime
/);

# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

sub ctime_obj {
    my ($self) = @_;
    return get_time($self->ctime());
}

1;
__END__
overview - Activity log imported into Reg from external (populated by the grab_new process).
id - Primary key
message - A human description of the external activity
cdate - Creation date
ctime - Creation time
