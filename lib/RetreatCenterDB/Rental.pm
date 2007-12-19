use strict;
use warnings;
package RetreatCenterDB::Rental;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('rental');
__PACKAGE__->add_columns(qw/
    id
    name
    title
    subtitle
    glnum
    sdate
    edate
    url
    webdesc
    linked
    phone
    email
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

1;
