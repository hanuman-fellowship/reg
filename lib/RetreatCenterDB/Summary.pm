use strict;
use warnings;
package RetreatCenterDB::Summary;
use base qw/DBIx::Class/;
use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;
use Util qw/
    expand
    ptrim
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('summary');
__PACKAGE__->add_columns(qw/
    id
    date_updated
    time_updated
    who_updated
    gate_code
    registration_location
    signage
    orientation
    wind_up
    alongside
    back_to_back
    leader_name
    staff_arrival
    staff_departure
    leader_housing
    food_service
    flowers
    miscellaneous
    feedback
    field_staff_std_setup
    field_staff_setup
    sound_setup
    check_list
    converted_spaces
    needs_verification
    prog_person
    workshop_schedule
    workshop_description
    date_sent
    time_sent
    who_sent
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(who_updated => 'RetreatCenterDB::User', 'who_updated');
__PACKAGE__->belongs_to(who_sent    => 'RetreatCenterDB::User', 'who_sent');
__PACKAGE__->might_have(rental  => 'RetreatCenterDB::Rental',  'summary_id');
__PACKAGE__->might_have(program => 'RetreatCenterDB::Program', 'summary_id');

sub     date_updated_obj { date(shift->date_updated) || ""; }
sub     time_updated_obj { get_time(shift->time_updated); }
sub     date_sent_obj { date(shift->date_sent) || ""; }
sub     time_sent_obj { get_time(shift->time_sent); }

#
# used in listing/summary.tt2
#
sub leader_housing_tr    { ptrim(shift->leader_housing()   ) };
sub flowers_tr           { ptrim(shift->flowers()          ) };
sub signage_tr           { ptrim(shift->signage()          ) };
sub field_staff_setup_tr { ptrim(shift->field_staff_setup()) };
sub food_service_tr      { ptrim(shift->food_service()     ) };
sub sound_setup_tr       { ptrim(shift->sound_setup()      ) };
sub workshop_description_tr { ptrim(shift->workshop_description()) };
sub workshop_schedule_tr { ptrim(shift->workshop_schedule()) };

#
# are there any pictures for this summary
# in root/static/images??
# if not return ""
# else return <tr> rows
# containing the <img> tags along
# links to enlarge them in a new window and
# links to delete them.
#
sub pictures {
    my ($self) = @_;
    my $id = $self->id();
    my @pics = <root/static/images/sth-$id-*>;
    if (!@pics) {
        return "";
    }
    my $pics1 = "";
    my $dels2 = "";
    for my $p (@pics) {
        my $mp = $p;
        $mp =~ s{^root}{};
        my ($n) = $mp =~ m{(\d+)[.]};
        $pics1 .= qq!<td align=center><a href="/summary/view_pic/$id/$n"><img src=$mp></a></td>!;
        $dels2 .= "<td align=center><a href=/summary/del_pic/$id/$n>Del</a></td>";
    }
    return <<"EOH";
<tr>
<th align=right valign=top>Pictures</th>
<td>
<table>
<tr>$pics1</tr>
<tr>$dels2</tr>
</table>
</td>
</tr>
EOH
}

sub needs_emailing {
    my ($self) = @_;
    if (! $self->date_sent) {
        return 1;
    }
    my $rc = $self->date_updated_obj <=> $self->date_sent_obj
             ||
             $self->time_updated_obj <=> $self->time_sent_obj;
    $rc > 0;
}

1;
__END__
overview - The summary contains all kinds of information that enable the MMC staff
    to be gracious and attentive hosts - for both rentals and programs.
    Lots of free text fields.
alongside - which other activities are alongside this event?
back_to_back - does another activity abutt this one?
check_list - things to not forget
converted_spaces - meeting rooms that become dorms
date_sent - when was this summary last sent?
date_updated - when was this summary last updated?
feedback - free text
field_staff_setup - free text
field_staff_std_setup - free text
flowers - free text
food_service - free text
gate_code - the gate code
id - unique id
leader_housing - free text
leader_name - free text
miscellaneous - free text
needs_verification - does this summary need to be verified?
    useful for when a template is copied into a new program/rental.
orientation - free text
prog_person - which person in the program office is in charge of this event?
registration_location - free text
signage - free text
sound_setup - free text
staff_arrival - free text
staff_departure - free text
time_sent - time last sent
time_updated - time last updated
who_sent - which user last sent - foreign key to user
who_updated - which user last updated - foreign key to user
wind_up - free text
workshop_description - free text
workshop_schedule - free text
