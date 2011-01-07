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

    ($self->h_type =~ m{tent}i)? 'site'
    :                            'room'
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

1;
