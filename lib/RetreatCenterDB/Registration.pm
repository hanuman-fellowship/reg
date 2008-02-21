use strict;
use warnings;
package RetreatCenterDB::Registration;
use base qw/DBIx::Class/;

use Date::Simple qw/date/;
use Lookup;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('registration');
# Set columns in table
__PACKAGE__->add_columns(qw/
    id
    person_id
    program_id
    referral
    adsource
    kids
    comment
    confnote
    h_type
    h_name
    work_study
    carpool
    hascar
    arrived
    cancelled
    date_postmark
    time_postmark
    balance
    date_start
    date_end
    ceu_license
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

#
# Set relationships:
#
__PACKAGE__->belongs_to(person   => 'RetreatCenterDB::Person', 'person_id');
__PACKAGE__->belongs_to(program  => 'RetreatCenterDB::Program','program_id');

__PACKAGE__->has_many(history =>  'RetreatCenterDB::RegHistory',  'reg_id');
__PACKAGE__->has_many(charges =>  'RetreatCenterDB::RegCharge',   'reg_id');
__PACKAGE__->has_many(payments => 'RetreatCenterDB::RegPayment',  'reg_id');

sub date_start_obj {
    my ($self) = @_;
    return date($self->date_start) || "";
}
sub date_end_obj {
    my ($self) = @_;
    return date($self->date_end) || "";
}

sub h_type_disp {
    my ($self) = @_;
    
    # Lookup->init();       # hopefully already done :(
    my $type = $lookup{$self->h_type};
    $type =~ s{\(.*\)}{};
    $type =~ s{Mount Madona }{};
    $type;
}

1;
