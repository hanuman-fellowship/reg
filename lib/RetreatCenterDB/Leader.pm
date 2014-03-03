use strict;
use warnings;
package RetreatCenterDB::Leader;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('leader');
__PACKAGE__->add_columns(qw/
    id
    person_id
    public_email
    url
    image
    biography
    assistant
    l_order
    just_first
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(leader_program => 'RetreatCenterDB::LeaderProgram',
                      'l_id');
__PACKAGE__->many_to_many(programs => 'leader_program', 'program',
                          { order_by => 'sdate desc' });
__PACKAGE__->belongs_to(person => 'RetreatCenterDB::Person', 'person_id');

sub name_public_email {
    my ($self) = @_;
    my $person = $self->person();
    return $person->first() . " " . $person->last()
         . " <" . $self->public_email() . ">";
}

#
# leaders are allowed to have only one name.
# normal people are not.
# is this fair? this is not egalitarian.
#
sub leader_name {
    my ($self) = @_;
    my $person = $self->person;
    if ($self->just_first) {
        return $person->first;
    }
    else {
        return $person->first . ' ' . $person->last;
    }
}

1;
__END__
overview - People can become Leaders of programs.
assistant - Is this person an assistant to another leader?
biography - Full bio.
id - unique id
image - is there a JPG of the person?  Naming conventions help locate the file.
just_first - Does this leader only use their first name?  e.g. Adyashanti
l_order - If a program has multiple leaders what order should they appear in?
person_id - foreign key to person
public_email - an email address for the leader that can be made public.
url - a web URL for the person
