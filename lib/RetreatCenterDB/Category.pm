use strict;
use warnings;
package RetreatCenterDB::Category;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('category');
__PACKAGE__->add_columns(qw/
    id
    name
/);
__PACKAGE__->set_primary_key(qw/id/);

1;
__END__
id - unique id
name - 
