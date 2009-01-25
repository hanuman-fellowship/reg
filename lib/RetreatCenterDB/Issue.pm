use strict;
use warnings;
package RetreatCenterDB::Issue;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('issue');
__PACKAGE__->add_columns(qw/
    id
    priority
    title
    notes
    date_entered
    date_closed
    user_id
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('user' => 'RetreatCenterDB::User', 'user_id');

sub date_entered_obj {
    my ($self) = @_;
    return date($self->date_entered) || "";
}

sub date_closed_obj {
    my ($self) = @_;
    return date($self->date_closed) || "";
}

sub notes_br { _br(shift->notes()); }

1;
