use strict;
use warnings;
package RetreatCenterDB::CheckOut;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('check_out');
__PACKAGE__->add_columns(qw/
    book_id
    person_id
    due_date
/);
__PACKAGE__->set_primary_key(qw/
    book_id
    person_id
/);

__PACKAGE__->belongs_to(book   => 'RetreatCenterDB::Book',   'book_id');
__PACKAGE__->belongs_to(person => 'RetreatCenterDB::Person', 'person_id');

sub due_date_obj {
    my ($self) = @_;
    return date($self->due_date()) || "";
}

1;
__END__
overview - A record here represents a book checked out to a person.
book_id - foreign key to book
due_date - When is the book due?
person_id - foreign key to person
