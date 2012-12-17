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

__PACKAGE__->belongs_to(user => 'RetreatCenterDB::User', 'user_id');

sub date_entered_obj {
    my ($self) = @_;
    return date($self->date_entered) || "";
}

sub date_closed_obj {
    my ($self) = @_;
    return date($self->date_closed) || "";
}

sub title_dq { _dq(shift->title()); }
sub title_esc_q { _esc_q(shift->title()); }
sub _dq {
    my ($s) = @_;
    $s =~ s{"}{&quot;}g;
    $s;
}
sub _esc_q {
    my ($s) = @_;
    $s =~ s{"}{\\"}g;
    $s;
}

1;
__END__
overview - This is a kind of bug tracking database so we don't forget
    what needs to be fixed.  It was used at first - until the issues grew too numerous.
    Email to the developer serves almost as well.
date_closed - date the issue was resolved
date_entered - date it was first logged
id - unique id
notes - Full explanation of what needs attention.
priority - 1 to 10 with 1 the most urgent.
title - Short description of the issue.
user_id - foreign key to user
