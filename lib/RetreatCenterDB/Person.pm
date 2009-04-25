use strict;
use warnings;
package RetreatCenterDB::Person;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;
use Algorithm::LUHN qw/
    is_valid
/;
use Util qw/
    valid_email
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('people');
__PACKAGE__->add_columns(qw/
    last
    first
    sanskrit
    addr1
    addr2
    city
    st_prov
    zip_post
    country
    akey
    tel_home
    tel_work
    tel_cell
    email
    sex
    id
    id_sps
    date_updat
    date_entrd
    comment
    e_mailings
    snail_mailings
    share_mailings
    deceased
    inactive
    cc_number
    cc_expire
    cc_code
/);
__PACKAGE__->set_primary_key(qw/id/);

# affiliations
__PACKAGE__->has_many(affil_person => 'RetreatCenterDB::AffilPerson', 'p_id');
__PACKAGE__->many_to_many(affils => 'affil_person', 'affil',
                          { order_by => 'descrip' },
                         );

# registrations
__PACKAGE__->has_many(registrations => 'RetreatCenterDB::Registration',
                      'person_id',
                      { order_by => 'date_start desc' });

# proposal submitter
__PACKAGE__->has_many(proposals => 'RetreatCenterDB::Proposal', 'person_id');

# rental coordinator
__PACKAGE__->has_many(rentals => 'RetreatCenterDB::Rental', 'coordinator_id');

# donations
__PACKAGE__->has_many(donations => 'RetreatCenterDB::Donation', 'person_id',
                      { order_by => 'the_date desc'});

# payments
__PACKAGE__->has_many(payments => 'RetreatCenterDB::XAccountPayment',
                                  'person_id',
                      { order_by => 'the_date desc'});
# rides
__PACKAGE__->has_many(rides => 'RetreatCenterDB::Ride',
                                  'rider_id',
                      { order_by => 'pickup_date'});

# MMI payments
__PACKAGE__->has_many(mmi_payments => 'RetreatCenterDB::MMIPayment',
                                      'person_id',
                      { order_by => 'the_date desc'});

# credits
__PACKAGE__->has_many(credits => 'RetreatCenterDB::Credit', 'person_id',
                      { order_by => 'date_given desc'});

# member - maybe
__PACKAGE__->might_have(member => 'RetreatCenterDB::Member', 'person_id');
# leader - maybe
__PACKAGE__->might_have(leader => 'RetreatCenterDB::Leader', 'person_id');
# partner - maybe
__PACKAGE__->might_have(partner => 'RetreatCenterDB::Person', 'id_sps');

#
# to make a multi-line column available
# for viewing from within a template
# by just using a different method name.
#
sub comment_br {
    my ($self) = @_;

    my $comment = $self->comment;
    $comment =~ s{\r?\n}{<br>\n}g;
    $comment;
}

sub date_updat_obj {
    my ($self) = @_;
    
    return date($self->date_updat);
}
sub date_entrd_obj {
    my ($self) = @_;

    return date($self->date_entrd);
}
sub cc_number1 { substr(shift->cc_number(),  0, 4) }
sub cc_number2 { substr(shift->cc_number(),  4, 4) }
sub cc_number3 { substr(shift->cc_number(),  8, 4) }
sub cc_number4 { substr(shift->cc_number(), 12, 4) }

sub addrs {
    my ($self) = @_;

    my $addrs = $self->addr1;
    if ($self->addr2) {
        $addrs .= " " . $self->addr2;
    }
    $addrs;
}

sub sex_disp {
    my ($self) = @_;

    my $sex = $self->sex;
    return ($sex eq 'M')? "Male"
          :($sex eq 'F')? "Female"
          :               "Person of Unreported Gender"
          ;
}

sub name_email {
    my ($self) = @_;
    return $self->first() . " " . $self->last() . "<" . $self->email() . ">";
}

sub email_okay {
    my ($self) = @_;

    my $email = $self->email();
    return valid_email($email)? $email: "";
}

#
# Address Verification System
#
sub avs {
    my ($self) = @_;
    my $addr = $self->addr1();
    my $zip  = $self->zip_post();
    for ($addr, $zip) {
        s{\D}{}g;
    }
    return "$addr $zip";
}

sub bad_cc {
    my ($self) = @_;
    return ! is_valid($self->cc_number());
}

1;
