use strict;
use warnings;
package RetreatCenterDB::File;
use base qw/DBIx::Class/;
use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('file');
__PACKAGE__->add_columns(qw/
    id
    rental_id
    program_id
    date_added
    time_added
    who_added
    filename
    suffix
    description
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(who_added => 'RetreatCenterDB::User', 'who_added');
__PACKAGE__->belongs_to(rental  => 'RetreatCenterDB::Rental',  'rental_id');
__PACKAGE__->belongs_to(program => 'RetreatCenterDB::Program', 'program_id');

sub date_added_obj { date(shift->date_added) || ""; }
sub time_added_obj { get_time(shift->time_added); }

__END__
overview - Files are added to a program or a rental
    They might be images or other documents of various kinds.
    Useful for information related to the event.
    Either program_id or rental_id is non-zero but not both.
date_added - date added
description - long description of the file
filename - base name of the file
id - unique id
program_id - the id of the program that owns this file
rental_id - the id of the rental that owns this file
suffix - suffix of the file
time_added - time added
who_added - foreign key of the user who added the file
