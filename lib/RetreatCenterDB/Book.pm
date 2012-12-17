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
overview - Books describe items in the MMC library.  Most columns below
    are self explanatory (marked se).
author - se (self-explanatory)
description - What's the book/video about?
id - unique id
location - Where in the MMC library can this item be found?
media - Book, VHS, DVD, or CD
publisher - se
subject - se
title - se
