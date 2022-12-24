use strict;
use warnings;
package RetreatCenterDB::Registration;
use base qw/DBIx::Class/;

use lib '..';

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
    empty
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
    badge_printed
    mountain_experience
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
__PACKAGE__->has_many(req_payments => 'RetreatCenterDB::RequestedPayment', 'reg_id',
                      { order_by => 'id desc' });
__PACKAGE__->has_many(confnotes => 'RetreatCenterDB::ConfHistory', 'reg_id',
                      { order_by => 'the_date desc, time desc' });

sub comment_tr {
    my ($self) = @_;
    return ptrim($self->comment());
}
#
# a trimmed comment for the Comings and Goings listing.
# can't predict the exact number of lines because the
# number will vary depending size of the browser window.
#
sub comment1 {
    my ($self) = @_;
    my $c = $self->comment();
    $c =~ s{\A (([^\n]*\n){3}).*}{$1}xms;        # only the first 3 lines
    $c =~ s{( <p>[&]nbsp;</p> | \s )* \z}{}xms;  # trim trailing "white space"
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

sub confnote_not_empty {
    my ($self) = @_;
    my $s = $self->confnote();
    $s =~ s{<[^>]*>}{}xmsg if $s;     # remove all html tags
    return ! empty($s);
}

sub deposit_disp {
    my ($self) = @_;
    # somehow the deposit might be NULL
    return $self->deposit() || 0;
}

my %ref_disp = (
    ad => 'Other',
    print_ad => 'Print Ad or Poster',
    social_media => 'Social Media',
    mmc_mmi_newsletter => 'MMC or MMI Newsletter',
    temple_newsletter => 'Temple Newsletter',
    hfs_newsletter => 'HFS Newsletter',
    radio => 'Radio',
    web => 'Web',
    brochure => 'Brochure',
    flyer => 'Flyer',
    word_of_mouth => 'Word of Mouth',
    other => 'Other',
);
sub referral_disp {
    my ($self) = @_;
    return $ref_disp{$self->referral};
}

sub h_type_disp {
    my ($self) = @_;
    
    my $type = $self->h_type;
    return "Unknown" if ! defined $type || ! exists $string{$type};
    $type = $string{$type};
}

sub site_cabin_room {
    my ($self) = @_;

    return if ! $self->house_id;
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
    my $bank = $reg->program->bank_account();
    if ($bank eq 'mmi' || $bank eq 'both') {
        for my $py ($reg->mmi_payments()) {
            $balance -= $py->amount;
        }
    }
    if ($bank eq 'mmc' || $bank eq 'both') {
        for my $py ($reg->payments()) {
            $balance -= $py->amount;
        }
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
        return $psdate->format("%B %e-") . trim($pedate->format("%e"));
    }
    else {
        return $psdate->format("%B %e - ") . $pedate->format("%B %e");
    }
}

sub dates {
    my ($self) = @_; 
    my $sdate = $self->date_start_obj;
    my $edate = $self->date_end_obj;
    if ($sdate == $edate) {
        return $sdate->format("%b %e");
    }
    return $sdate->format("%b %e")
         . ' - '
         . $edate->format("%b %e")
         ;
}

sub receipt_dates {
    my ($self) = @_;
    my $prog = $self->program();
    my $PR = $prog->PR();
    my $psdate = $PR? $self->date_start_obj(): $prog->sdate_obj();
    my $pedate = $PR? $self->date_end_obj()  : $prog->edate_obj();
    my $diff_mon = $psdate->month() != $pedate->month();
    my $diff_yr = $psdate->year() != $pedate->year();
    my $s = $psdate->format("%B %e" . ($diff_yr? ", %Y": ""));
    my $e = $pedate->format(($diff_mon? "%B %e": "%e") . ", %Y");
    return $s . " - " . $e;
}

sub house_name {
    my ($self) = @_;
    my $h = $self->house;
    my $p = $self->person;
    my $h_type = $self->h_type;
    my $h_name;
    if ($h_type eq 'own_van') {
        $h_name = 'Own Van';
    }
    elsif ($h_type eq 'commuting') {
        $h_name = 'Commuting';
    }
    elsif ($h_type eq 'unknown' || $h_type eq 'not_needed') {
        $h_name = 'No Housing';
    }
    elsif (! $h) {
        $h_name = '??';
    }
    else {
        $h_name = $h->name;
        my $cluster_name = $h->cluster->name;
        if ($cluster_name =~ m{Conference}xms) {
            $h_name = 'CC ' . $h_name;
            $h_name =~ s{[BH]+ \z}{}xms;
        }
    }
    return $h_name;
}

# extract the Yoga Class, Guided Walk from the HTML comment
# which may have other things in it
sub activity {
    my ($self) = @_;
    my $s = $self->comment();
    my @act;
    push @act, $s =~ m{(Yoga\s+Class)}xmsi;
    push @act, $s =~ m{(Guided\s+Walk)}xmsi;
    return join ', ', @act;
}

sub heard {
    my ($self) = @_;
    my $s = $self->referral;
    if ($s eq 'ad') {
        $s = $self->adsource;
    }
    if (empty($s)) {
        $s = '';        # ? doesn't look good - so blank
    }
    return ucfirst $s;
}

1;
__END__
overview - A registration is created when a Person signs up for a Program.
    This is a central record that has many relations to other tables (i.e. Models/Objects).
adsource - how did they find out about the program?
arrived - have they arrived at MMC?
badge_printed - Has the badge been printed for this person?
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
mountain_experience - what meals do they want? Lunch and/or Dinner
    if empty - not a mountain experience
nights_taken - How many member benefit nights were taken?
person_id - foreign key to person
pref1 - housing preference #1 - see h_type
pref2 - housing preference #2 - see h_type
program_id - foreign key to program
referral - advertisement, web, brochure, or flyer, etc.
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
