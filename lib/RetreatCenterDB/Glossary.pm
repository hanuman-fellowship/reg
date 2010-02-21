use strict;
use warnings;
package RetreatCenterDB::Glossary;
use base qw/DBIx::Class/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('glossary');
# Set columns in table
__PACKAGE__->add_columns(qw/
    term
    definition
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/term/);

1;
