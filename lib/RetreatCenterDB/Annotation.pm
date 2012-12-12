use strict;
use warnings;
package RetreatCenterDB::Annotation;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('annotation');
__PACKAGE__->add_columns(qw/
    id
    cluster_type
    label
    x
    y
    x1
    y1
    x2
    y2
    shape
    thickness
    color
    inactive
/);
__PACKAGE__->set_primary_key('id');

1;
__END__
cluster_type - 
color - 
id - unique id
inactive - 
label - 
shape - 
thickness - 
x - 
x1 - 
x2 - 
y - 
y1 - 
y2 - 
