use strict;
use warnings;
package RetreatCenterDB::Inquiry;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time 
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('inquiry');
__PACKAGE__->add_columns(qw/
   id
   the_date
   the_time
   leader_name
   phone
   email
   group_name
   dates
   description
   how_many
   vegetarian
   retreat_type
   needs
   learn
   what_else
   notes
   status
   person_id
   rental_id
   comm
   mailing_list
   first
   last
   website
   event_name
   flexdates
   optdates
   group_type
   services
/);
__PACKAGE__->set_primary_key(qw/id/);

sub website_plus {
    my ($self) = @_;
    my $ws = $self->website;
    if ($ws && $ws !~ m{http}xms) {
        $ws = "https://$ws";
    }
    return $ws;
}

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date) || "";
}

sub the_time_obj {
    my ($self) = @_;
    return get_time($self->the_time) || "";
}

my @status = (
    'New',              # 0
    'Contacted',        # 1
    'Engaged',          # 2
    'Denied by Host',   # 3
    'Denied by MMC',    # 4
    'Tentative',        # 5
    'Rental',           # 6
    'Priority',         # 7
    'Dates Proposed',   # 8
);

sub status_disp {
    my ($self) = @_;
    return $status[$self->status];
}
# class method?
sub statuses {
    my ($self) = @_;
    return @status;
}

sub csv {
    my ($self) = @_;
    my $csv = '';
    my $tab = "\t";
    $csv .= date($self->the_date)->format("%F")
         .  $tab 
         .  get_time($self->the_time)->t24()
         . $tab
         ;
    for my $f (qw/
        leader_name phone email
        notes status_disp group_name
        dates description
        how_many vegetarian
        retreat_type needs
        learn what_else
    /) {
        my $s = $self->$f;
        $s =~ s{\cM}{}xmsg;
        $csv .= "$s\t";
    }
    chop $csv;      # the final tab
    return $csv;
}

1;
__END__
overview - Inquiries are filled out online and then a row is entered
    into this database table.  Better than a Proposal in a way.
comm - Discovery call communication choice
dates - what dates (roughly) are requested?
description - brief description of the retreat
email - email of the leader
event_name - name of their event
first - first name of leader
flexdates - Are the dates flexible?
group_name - name of the group
group_type - type of the group
how_many - size of the group
id - unique id
last - last name of leader
learn - how did they learn of MMC?
leader_name - name of leader - OBSOLETE - first/last
mailing_list - Add to mailing list?
needs - various things they need
notes - added by MMC after receiving the inquiry
optdates - Optional dates and notes
person_id - id of the Person record for the leader
phone - phone number of the leader
rental_id - if converted - the id of the rental
retreat_type - type of retreat - possibly more than one
services - additional services
status - integer index into status array
    New, Contacted, Engaged, Denied by Host, Denied by MMC, Tentative, Rental
the_date - the date the inquiry came in
the_time - the time the inquiry came in
vegetarian - boolean yes/'' - must be 'yes'
website - URL of their website
what_else - what else did they want us to know?
