use strict;
use warnings;
package RetreatCenterDB::Exception;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('exception');
__PACKAGE__->add_columns(qw/
    prog_id
    tag
    value
/);

__PACKAGE__->belongs_to(program => 'RetreatCenterDB::Program', 'prog_id');

1;
__END__
overview - When a program web page is generated you may want to
    make an exception for a particular program and a particular tag
    within the web page template.
prog_id - foreign key to program
tag - the tag name
value - the replacement value
