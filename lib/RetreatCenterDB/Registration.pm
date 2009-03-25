use strict;
use warnings;
package RetreatCenterDB::Registration;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;
use Global qw/
    %string
/;
use Util qw/
    trim
    expand
/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('registration');
# Set columns in table
__PACKAGE__->add_columns(qw/
    id
    person_id
    program_id
    deposit
    referral
    adsource
    kids
    comment
    confnote
    h_type
    h_name
    carpool
    hascar
    arrived
    cancelled
    date_postmark
    time_postmark
    balance
    date_start
    date_end
    early
    late
    ceu_license
    letter_sent
    status
    nights_taken
    free_prog_taken
    house_id
    cabin_room
    leader_assistant
    pref1
    pref2
    share_first
    share_last
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

#
# Set relationships:
#
__PACKAGE__->belongs_to(person   => 'RetreatCenterDB::Person', 'person_id');
__PACKAGE__->belongs_to(program  => 'RetreatCenterDB::Program','program_id');
__PACKAGE__->belongs_to(house    => 'RetreatCenterDB::House',  'house_id');

__PACKAGE__->has_many(history   => 'RetreatCenterDB::RegHistory',  'reg_id');
__PACKAGE__->has_many(charges   => 'RetreatCenterDB::RegCharge',   'reg_id');
__PACKAGE__->has_many(payments  => 'RetreatCenterDB::RegPayment',  'reg_id');
__PACKAGE__->has_many(confnotes => 'RetreatCenterDB::ConfHistory', 'reg_id',
                      { order_by => 'the_date desc, time desc' });

sub date_start_obj {
    my ($self) = @_;
    return date($self->date_start) || "";
}
sub date_end_obj {
    my ($self) = @_;
    return date($self->date_end) || "";
}
sub date_postmark_obj {
    my ($self) = @_;
    return date($self->date_postmark) || "";
}
sub time_postmark_obj {
    my ($self) = @_;
    return get_time($self->time_postmark());
}

sub h_type_disp {
    my ($self) = @_;
    
    my $type = $self->h_type;
    return "Unknown" if ! defined $type || ! exists $string{$type};
    $type = $string{$type};
}

sub room_site {
    my ($self) = @_;

    ($self->h_type =~ m{tent}i)? 'site'
    :                            'room'
}

sub pref1_sh {
    my ($self) = @_;
    my $s = $string{$self->pref1()};
    $s =~ s{ \(.*}{};
    $s;
}
sub pref2_sh {
    my ($self) = @_;
    my $s = $string{$self->pref2()};
    $s =~ s{ \(.*}{};
    $s;
}

1;
