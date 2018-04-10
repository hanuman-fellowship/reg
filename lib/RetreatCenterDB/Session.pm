package RetreatCenterDB::Session;
 
use base qw/DBIx::Class/;
 
__PACKAGE__->load_components(qw/Core/);
__PACKAGE__->table('sessions');
__PACKAGE__->add_columns(qw/
    id
    session_data
    expires
/);
__PACKAGE__->set_primary_key('id');
 
1;
__END__
overview - table to keep track of sessions
expires - when does this session expire?
id - primary key
session_data - serialized session of session - login id, etc
