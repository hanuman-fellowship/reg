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

sub room_site {
    my ($self) = @_;

    ($self->h_type =~ m{tent}ixms)? 'site'
    :                               'room'
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
    return $psdate->format("%B %e - ")
         . ($psdate->month() == $pedate->month()? $pedate->format("%e")
            :                                     $pedate->format("%B %e"))
         ;
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
overview - 
adsource - 
arrived - 
balance - 
cabin_room - 
cancelled - 
carpool - 
ceu_license - 
comment - 
confnote - 
date_end - 
date_postmark - 
date_start - 
deposit - 
early - 
free_prog_taken - 
from_where - 
h_name - 
h_type - 
hascar - 
house_id - foreign key to house
id - unique id
kids - 
late - 
leader_assistant - 
letter_sent - 
manual - 
nights_taken - 
person_id - foreign key to person
pref1 - 
pref2 - 
program_id - foreign key to program
referral - 
rental_after - 
rental_before - 
share_first - 
share_last - 
status - 
time_postmark - 
transaction_id - Authorize.net transaction id
work_study - 
work_study_comment - 
work_study_safety - 
