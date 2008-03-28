use strict;
use warnings;
package RetreatCenterDB::ConfHistory;
use base qw/DBIx::Class/;

use Date::Simple qw/date/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('conf_history');
__PACKAGE__->add_columns(qw/
    id
    reg_id
    note
    user_id
    the_date
    time
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('registration' => 'RetreatCenterDB::Registration', 'reg_id');
__PACKAGE__->belongs_to('user' => 'RetreatCenterDB::User', 'user_id');

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date);
}

sub note_br {
    my ($self) = @_;
    my $note = $self->note;
    $note =~ s{\r?\n}{<br>\n}g;
    if ($note && $note !~ m{<br>$}) {
        $note .= "<br>";
    }
    $note;
}

1;
