use strict;
use warnings;
package RetreatCenterDB::XAccount;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('xaccount');
__PACKAGE__->add_columns(qw/
    id
    descr
    glnum
    sponsor
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key('id');

sub SPONSOR {
    my ($self) = @_;
    uc $self->sponsor();
}

1;
__END__
overview - An extra account is a place to put miscellaneous monies that come into the center.
    Monies are put into these accounts by creating a XAccountPayment (which has a foreign key to XAccount).
descr - A brief description of the account.
glnum - A General Ledger number assigned by an account_admin.
id - unique id
sponsor - "mmc" or "mmi"
