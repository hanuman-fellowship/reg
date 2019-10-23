use strict;
use warnings;
package RetreatCenterDB::Person;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;
use Util qw/
    empty
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
    safety_form
    secure_code
    temple_id
    waiver_signed
    only_temple
/);
# didn't work??? - check_doc complains as well...
#__PACKAGE__->add_columns(
#    deceased => { data_type => 'text', is_nullable => 1, },
#);
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

# MMI payments
__PACKAGE__->has_many(mmi_payments => 'RetreatCenterDB::MMIPayment',
                                      'person_id',
                      { order_by => 'the_date desc'});

# Requested Payments MMC/MMI
__PACKAGE__->has_many(req_payments => 'RetreatCenterDB::RequestedPayment',
                                      'person_id',
                      { order_by => 'the_date desc'});

# credits
__PACKAGE__->has_many(credits => 'RetreatCenterDB::Credit', 'person_id',
                      { order_by => 'date_given desc'});

# member - maybe
__PACKAGE__->might_have(member => 'RetreatCenterDB::Member', 'person_id');
# leader - maybe
__PACKAGE__->might_have(leader => 'RetreatCenterDB::Leader', 'person_id');
# resident - maybe
__PACKAGE__->might_have(resident => 'RetreatCenterDB::Resident', 'person_id');
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
    $comment =~ s{\r?\n}{<br>\n}g if $comment;
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

    my $sex = $self->sex || '';
    return ($sex eq 'M')? "Male"
          :($sex eq 'F')? "Female"
          :($sex eq 'X')? "Non-Binary"
          :               "Person of Unreported Gender"
          ;
}

sub name {
    my ($self) = @_;
    return $self->first() . ' ' . $self->last();
}

sub last_first_name {
    my ($self) = @_;
    return $self->last() . ', ' . $self->first();
}

sub badge_name {
    my ($self, $no_sanskrit) = @_;
    my $name = $self->name();
    if (! $no_sanskrit && $self->sanskrit()) {
        $name = $self->sanskrit() . ' ' . $name;
    }
    return $name;
}

sub name_email {
    my ($self) = @_;
    return $self->name() . ' <' . $self->email() . '>';
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

sub carpool_telephone {
    my ($self) = @_;

    for my $t (qw/ home work cell /) {
        my $method = "tel_$t";
        if (my $s = $self->$method()) {
            return "$s $t<br>";
        }
    }
    return "";
}

sub numbers {
    my ($self) = @_;

    my $n = 0;
    ++$n if $self->tel_home;
    ++$n if $self->tel_work;
    ++$n if $self->tel_cell;
    return $n == 1? "this is the number"
          :         "these are the numbers"
          ;
}

1;
__END__
overview - The person record contains all the personal information
    that we need to know about people in our database.  
    Many other tables have a foreign key into person.
    See the many Relations below.
    <p>
    <p>The table name is people but the model name is Person.
    We don't have a strict naming convention for table/model names
    like Ruby on Rails does.
addr1 - first line of address
addr2 - optional second line of address
akey - a computed key used for address unduplication
city - city
comment - arbitrary length comment about the person
country - country
date_entrd - date this person's record was first entered
date_updat - last date the record was updated
deceased - the person has passed
e_mailings - I want MMC emailings
email - email address
first - first name
id - unique id
id_sps - foreign key to person - the partner, if partnered
inactive - This record is no longer active - for whatever reason.
    Do not include it in any mailings.
last - last name
only_temple - Is this person ONLY a Temple Guest?
safety_form - this person has filled out a safety form
sanskrit - Sanskrit name - if any.
    one can search for a person by their Sanskrit name
secure_code - generated at record creation time - 6 random letters
    Used for sending in email for online member payment and also
    for having people update their own People entry.
sex - gender - M or F.
    for people that have as yet not specified their gender
    this field could be either blank ' ' or C (not sure why old reg had a C - couple?).
    this field matters for housing purposes.
share_mailings - it is okay to share my information with other organizations
snail_mailings - I want MMC snail mailings
st_prov - state or province
tel_cell - cell phone
tel_home - home phone
tel_work - work phone
    These phone numbers are used in many places.
    Especially in the phone list, of course.
temple_id - the unique id in the temple visitor database.
    not all people will have one - only those who have reserved
    a visit to the temple.  used in grab_new.
waiver_signed - they signed a waiver of liability (yoga programs)
zip_post - zip (or postal) code
