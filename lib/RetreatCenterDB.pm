use strict;
use warnings;
package RetreatCenterDB;

use base 'DBIx::Class::Schema';

my @classes = qw/
    Affil 
    AffilPerson 
    Person 
    Report 
    AffilReport
    User
    UserRole
    Role
    Program
    CanPol
    HouseCost
    AffilProgram
    Leader
    LeaderProgram
    ConfNote

    Rental
    RentalPayment
    RentalCharge
    Proposal

    Summary

    Exception
    String

    Registration
    RegHistory
    RegPayment
    RegCharge
    Credit
    ConfHistory

    Member
    SponsHist
    NightHist
    Project
    Donation

    Event
    XAccount
    XAccountPayment

    Deposit

    MeetingPlace
    Booking

    House
    Cluster
    Config
    RentalBooking
    RentalCluster
    ProgramCluster
    Annotation

    MakeUp

    MMIPayment

    Issue
    Ride

    Block

    Book
    CheckOut

    Glossary

    Resident
    Category
    ResidentNote

    RequestedMMIPayment

    Organization
    ProgramDoc
/;

__PACKAGE__->load_classes({
    RetreatCenterDB => \@classes,
});

sub classes {
    my ($self) = @_;
    return \@classes;
}

# Created by DBIx::Class::Schema::Loader v0.04002 @ 2007-10-25 19:22:28
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:QCxMJEGA7D4BomDZLbw6VQ
# You can replace this text with custom content, and it will be preserved on regeneration
1;
