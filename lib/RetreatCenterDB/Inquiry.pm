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
/);
__PACKAGE__->set_primary_key(qw/id/);

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date) || "";
}

sub the_time_obj {
    my ($self) = @_;
    return get_time($self->the_time) || "";
}

my @status = qw/
    New
    Contacted
    Denied
    Tentative
    Rental
/;
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
dates - what dates (roughly) are requested?
description - brief description of the retreat
email - email of the leader
group_name - name of the group
how_many - size of the group
id - unique id
learn - how did they learn of MMC?
leader_name - name of leader
needs - various things they need
notes - added by MMC after receiving the inquiry
person_id - id of the Person record for the leader
phone - phone number of the leader
rental_id - if converted - the id of the rental
retreat_type - type of retreat - possibly more than one
status - integer index into status array
    New, Contacted, Denied, Tentative, Rental
the_date - the date the inquiry came in
the_time - the time the inquiry came in
vegetarian - boolean yes/'' - must be 'yes'
what_else - what else did they want us to know?
