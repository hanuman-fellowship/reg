use strict;
use warnings;
package RetreatCenterDB::Project;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('project');
__PACKAGE__->add_columns(qw/
    id
    descr
    glnum
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(donations => 'RetreatCenterDB::Donation', 'project_id',
                          { order_by => 'the_date desc'});

1;
__END__
overview - 
descr - 
glnum - 
id - unique id
