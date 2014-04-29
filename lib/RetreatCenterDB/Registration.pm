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
    ptrim
    penny
    model
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
    manual
    work_study
    work_study_comment
    work_study_safety
    rental_before
    rental_after
    transaction_id
    from_where
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

#
# Set relationships:
#
__PACKAGE__->belongs_to(person   => 'RetreatCenterDB::Person', 'person_id');
__PACKAGE__->belongs_to(program  => 'RetreatCenterDB::Program','program_id');
__PACKAGE__->belongs_to(house    => 'RetreatCenterDB::House',  'house_id');

__PACKAGE__->has_many(history   => 'RetreatCenterDB::RegHistory',  'reg_id',
                      { order_by => 'the_date desc, time desc, id desc'});

__PACKAGE__->has_many(charges   => 'RetreatCenterDB::RegCharge',   'reg_id');
__PACKAGE__->has_many(payments  => 'RetreatCenterDB::RegPayment',  'reg_id');
__PACKAGE__->has_many(mmi_payments  => 'RetreatCenterDB::MMIPayment',
                      'reg_id');
__PACKAGE__->has_many(req_mmi_payments => 'RetreatCenterDB::RequestedMMIPayment', 'reg_id',
                      { order_by => 'id desc' });
__PACKAGE__->has_many(confnotes => 'RetreatCenterDB::ConfHistory', 'reg_id',
                      { order_by => 'the_date desc, time desc' });

sub comment_tr {
    my ($self) = @_;
    return ptrim($self->comment());
}
sub comment1 {
    my ($self) = @_;
    my $c = $self->comment();
    $c =~ s{\n.*}{\n};      # only the first line, please
    $c =~ s{([.!?]).*}{$1};     # only the first sentence, please.
                                # since lines depend on a </p> or \n
                                # those are not always there.
    $c;
}
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

sub site_cabin_room {
    my ($self) = @_;

    my $house = $self->house;
    return $house->tent ? 'SITE'
          :$house->cabin? 'CABIN' 
          :               'ROOM'
          ;
}

sub pref1_sh {
    my ($self) = @_;
    my $pref = $self->pref1();
    if (! $pref || ! exists $string{$pref}) {
        return "";
    }
    my $s = $string{$pref};
    $s =~ s{ \(.*}{};
    $s;
}
sub pref2_sh {
    my ($self) = @_;
    my $pref = $self->pref2();
    if (! $pref || ! exists $string{$pref}) {
        return "";
    }
    my $s = $string{$pref};
    $s =~ s{ \(.*}{};
    $s;
}

sub calc_balance {
    my ($reg) = @_;

    # calculate the balance, update the reg record
    my $balance = 0;
    for my $ch ($reg->charges) {
        $balance += $ch->amount;
    }
    my $payments = ($reg->program->school() != 0)? "mmi_payments"
                  :                                "payments"
                  ;
    for my $py ($reg->$payments) {
        $balance -= $py->amount;
    }
    $reg->update({
        balance => $balance,
    });
}

sub balance_disp {
    my ($self) = @_;
    penny($self->balance());
}

sub from_where_verbose {
    my ($self) = @_;
    my $fw = $self->from_where();
    if ($fw eq 'SJC') {
        return 'San Jose';
    }
    elsif ($fw eq 'SFO') {
        return 'San Francisco';
    }
    else {
        return $fw;
    }
}

#
# this sub is only called for non-PR programs.
# return the dates of the program that this person is attending.
# be careful of a program with extra days.
#
sub att_prog_dates {
    my ($self) = @_;
    my $prog = $self->program();
    my $psdate = $prog->sdate_obj();
    my $pedate = $prog->edate_obj();
    if ($self->date_end() > $prog->edate() && $prog->extradays()) {
        # this registration is attending the extra days of the program
        # not just staying late after a program without extra days.
        #
        $pedate = $prog->edate_obj() + $prog->extradays();
    }
    if ($psdate->month == $pedate->month) {
        return $psdate->format("%B %e-") . $pedate->format("%e");
    }
    else {
        return $psdate->format("%B %e - ") . $pedate->format("%B %e");
    }
}

sub receipt_dates {
    my ($self) = @_;
    my $prog = $self->program();
    my $psdate = $prog->sdate_obj();
    my $pedate = $prog->edate_obj();
    my $diff_mon = $psdate->month() != $pedate->month();
    my $diff_yr = $psdate->year() != $pedate->year();
    my $s = $psdate->format("%B %e" . ($diff_yr? ", %Y": ""));
    my $e = $pedate->format(($diff_mon? "%B %e": "%e") . ", %Y");
    return $s . " - " . $e;
}

1;
__END__
overview - A registration is created when a Person signs up for a Program.
    This is a central record that has many relations to other tables (i.e. Models/Objects).
adsource - how did they find out about the program?
arrived - have they arrived at MMC?
balance - balance due
cabin_room - do they prefer a cabin or a room?  the value is cabin, room, or empty
cancelled - has this registration been cancelled?
carpool - do they want to carpool?
ceu_license - a text field with the license number, if any - for CEU certificates.
comment - a free text field for a variety of purposes to describe
    issues with this registration
confnote - A free text note to insert at the top of the confirmation letter.
date_end - when will the person leave?
date_postmark - when was the registration taken?
date_start - when will the person arrive?
deposit - How much was paid in the deposit?
    This value is duplicated in a RegPayment record.
early - will this person come before the program starts?
free_prog_taken - was this person a Member and they took this program as
    their free program?
from_where - Home, SJC, SFO, or empty.   Where do you want to car pool from?
h_name - House name.  Used in old reg.   Now obsolete.
h_type - housing type - one of:
    <ul>
    <li>unknown
    <li>commuting
    <li>own_tent
    <li>dormitory
    <li>economy
    <li>center_tent
    <li>triple
    <li>own_van
    <li>single
    <li>dble
    <li>single_bath
    <li>dble_bath
    <li>unknown_bath
    <li>quad
    <li>triple_bath
    <li>not_needed
    </ul>
hascar - do they have a car?  (for car pooling)
house_id - foreign key to house
id - unique id
kids - ages of kids accompanying the registrant.
late - will this person leave on the day the program ends?
leader_assistant - is this person a leader or assistant?
letter_sent - was the confirmation letter sent?  old record have a date.
    it is now a boolean field.
manual - should the finances not be done automatically?
nights_taken - How many member benefit nights were taken?
person_id - foreign key to person
pref1 - housing preference #1 - see h_type
pref2 - housing preference #2 - see h_type
program_id - foreign key to program
referral - advertisement, web, brochure, or flyer.
    if ad then the ad_source is also filled in.
rental_after - is this person staying for a rental after this program?  (usually a personal retreat)
rental_before - was this person here for a rental before this program?  (usually a personal retreat)
share_first - first name of the person they want to share a room with
share_last - last name of the person they want to share a room with
status - membership status - empty, Sponsor, Life, Founding Life
time_postmark - what time did the initial registration happen?
transaction_id - Authorize.net transaction id
work_study - do they want to do work study?
work_study_comment - what kind of work do they want to do?
work_study_safety - have they filled in a safety form?  This is in synchrony with
    the safety_form field of Person.
