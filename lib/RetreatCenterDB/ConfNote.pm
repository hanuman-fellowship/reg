use strict;
use warnings;
package RetreatCenterDB::ConfNote;

use base qw/DBIx::Class/;

use Util qw/
    _br
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('confnote');
__PACKAGE__->add_columns(qw/
    id
    abbr
    expansion
/);

__PACKAGE__->set_primary_key('id');

sub expansion_br {
    _br(shift->expansion);
}

1;
__END__
overview - These records provide a short alias for a commonly used long piece of text in
    the confirmation letter notes.
abbr - the short
expansion - the long
id - unique id
