use strict;
use warnings;
package RetreatCenterDB::Book;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('book');
__PACKAGE__->add_columns(qw/
    id
    title
    author
    publisher
    location
    subject
    description
    media
/);
__PACKAGE__->set_primary_key(qw/
    id
/);

1;
__END__
author - 
description - 
id - unique id
location - 
media - 
publisher - 
subject - 
title - 
