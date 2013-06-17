use strict;
use warnings;
package RetreatCenterDB::ProgramDoc;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('program_doc');
__PACKAGE__->add_columns(qw/
    id
    program_id
    title
    suffix
/);
__PACKAGE__->set_primary_key(qw/
    id
/);

__PACKAGE__->belongs_to(program => 'RetreatCenterDB::Program', 'program_id');

1;
__END__
overview - A document that is attached to a program.  It is uploaded
    to the web and a link is made to it on the program's web page.
id - unique id
program_id - foreign key to program
suffix - the file extension of the document (e.g. jpg or pdf)
title - The description of the document - used as a link target on the web page.
