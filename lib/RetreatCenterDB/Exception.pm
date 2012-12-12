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

__PACKAGE__->belongs_to('program' => 'RetreatCenterDB::Program', 'prog_id');

1;
__END__
prog_id - foreign key to program
tag - 
value - 
