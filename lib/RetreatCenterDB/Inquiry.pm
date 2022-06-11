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
phone - phone number of the leader
retreat_type - type of retreat - possibly more than one
the_date - the date the inquiry came in
the_time - the time the inquiry came in
vegetarian - boolean yes/'' - must be 'yes'
what_else - what else did they want us to know?
