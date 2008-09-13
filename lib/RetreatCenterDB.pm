use strict;
use warnings;
package RetreatCenterDB;

use base 'DBIx::Class::Schema';

__PACKAGE__->load_classes({
    RetreatCenterDB => [qw/
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
    /]
});

# Created by DBIx::Class::Schema::Loader v0.04002 @ 2007-10-25 19:22:28
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:QCxMJEGA7D4BomDZLbw6VQ

sub connect {
    open my $out, ">", "/tmp/jonn" or die "no /tmp/jonn: $!\n";
    print {$out} "hi\n";
    my $new = shift->next::method(@_);
    my @all_users = $new->resultset('User')->all();
    for my $u (@all_users) {
        print {$out} $u->name(), "\n";
    }
    close $out;
    return $new;
}

# You can replace this text with custom content, and it will be preserved on regeneration
1;
