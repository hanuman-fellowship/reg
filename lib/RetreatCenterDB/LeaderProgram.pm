use strict;
use warnings;
package RetreatCenterDB::LeaderProgram;
use base qw/DBIx::Class/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('leader_program');
# Set columns in table
__PACKAGE__->add_columns(qw/
    l_id
    p_id
/);
#
# Set relationships:
#
__PACKAGE__->belongs_to(program => 'RetreatCenterDB::Program', 'p_id');
__PACKAGE__->belongs_to(leader  => 'RetreatCenterDB::Leader',  'l_id');


1;
__END__
overview - 
l_id - foreign key to leader
p_id - foreign key to program
