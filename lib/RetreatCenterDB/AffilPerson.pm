package RetreatCenterDB::AffilPerson;
use base qw/DBIx::Class/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('affil_people');
# Set columns in table
__PACKAGE__->add_columns(qw/
    a_id
    p_id
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/a_id p_id/);

#
# Set relationships:
#
__PACKAGE__->belongs_to(person => 'RetreatCenterDB::Person', 'p_id');
__PACKAGE__->belongs_to(affil  => 'RetreatCenterDB::Affil',  'a_id');

=head1 NAME

RetreatCenterDB::AffilPerson - A model object representing a ???.

=head1 DESCRIPTION

This is an object that represents a row in the 'books' table of your application
database.  It uses DBIx::Class (aka, DBIC) to do ORM.

For Catalyst, this is designed to be used through MyApp::Model::MyAppDB.
Offline utilities may wish to use this class directly.

=cut

1;
