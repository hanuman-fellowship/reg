use strict;
use warnings;
package RetreatCenterDB::GiftCards;
use base qw/DBIx::Class/;


# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('gift_cards');
# Set columns in table
__PACKAGE__->add_columns(qw/
    id
    person_id
    code
    amount
    rec_fname
    rec_lname
    rec_email
    the_date
    the_time
    transaction_id
    reg_id
/);

# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

sub the_time_obj {
    my ($self) = @_;
    return get_time($self->the_time());
}

sub the_date_obj {
    my ($self) = @_;
    return get_time($self->the_date());
}

__PACKAGE__->belongs_to(person   => 'RetreatCenterDB::Person', 'person_id');

1;
__END__
overview - Gift Cards - for lodging for PRs and other programs
    either transaction_id or reg_id will be non-zero
id - Primary key
person_id - foreign key to Person
code - the 5 character code of the card
amount - the dollar value of the card
rec_fname - first name of the recipient
rec_lname - last name of the recipient
rec_email - email of the recipient
reg_id - foreign key to Registration (optional)
the_date - date purchase was made
the_time - time purchase was made
transaction_id - authorize.net transaction id for online payments (optional)
