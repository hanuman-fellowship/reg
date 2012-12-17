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
overview - Annotations are markings on the DailyPic of various shapes and colors.
    There are 4 hard coded cluster types: Indoors, Outdoors, Special, and Resident.
    The X/Y coordinates determine where the drawing will take place and the size.
    The annotations are loaded in lib/Global.pm and used in Controller/DailyPic.pm.
cluster_type - Which daily pic?
color - The RGB values for the color.
id - unique id
inactive - active or not?
label - Text to display.
shape - None (text), Rectangle, or Ellipse
thickness - of the line
x - for the text
x1 - for the rectangle/ellipse
x2 - for the rectangle/ellipse
y - for the text
y1 - for the rectangle/ellipse
y2 - for the rectangle/ellipse
