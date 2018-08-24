use strict;
use warnings;
package DB::Role;
use DBH;

sub order { 1 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS role;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE role (
id integer primary key auto_increment,
role varchar(20),
fullname varchar(30),
descr varchar(1000)
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO role
(role, fullname, descr) 
VALUES
(?, ?, ?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my (@fields) = split /\|/, $line, -1;
        $sth->execute(@fields);
    }
}

1;

__DATA__
super_admin|Super Admin|Create users and roles.
prog_admin|Program Admin|Create programs, rentals, leaders, cancellation policies, housing costs, housing configuration, and can publish to staging.
mail_admin|Mailing List Admin|Create affiliations, can do a purge and stale
prog_staff|Program Staff|Does registrations, finances, housing
mail_staff|Mailing List Staff|People create/edit/delete, partnering, affiliations
web_designer|Web Designer|Templates, web images, exceptions, strings
member_admin|Membership Admin|Maintain Memberships
field_staff|Field Staff|Room Makeup, Campsite Tidying
mmi_admin|MMI Admin|MMI Administration
kitchen|Kitchen|Kitchen Admin
developer|Software Developer|Those who create the software.
driver|Driver|Give Rides To and From
ride_admin|Ride Admin|Arrange Rides To and From
user_admin|User Admin|Create/Edit Users
librarian|Librarian|adds and edits books
personnel_admin|Personnel Admin|Administer Personnel Issues
event_scheduler|Event Scheduler|Schedules events for all organizations
account_admin|Account Admin|creates Extra Accounts
time_traveler|Time Traveler|People who can travel through time
