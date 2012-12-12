use strict;
use warnings;
package RetreatCenterDB::AffilProgram;
use base qw/DBIx::Class/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('affil_program');
# Set columns in table
__PACKAGE__->add_columns(qw/
    a_id
    p_id
/);
#
# Set relationships:
#
__PACKAGE__->belongs_to(program => 'RetreatCenterDB::Program', 'p_id');
__PACKAGE__->belongs_to(affil  => 'RetreatCenterDB::Affil',  'a_id');


1;
__END__
a_id - foreign key to affil
p_id - foreign key to program
