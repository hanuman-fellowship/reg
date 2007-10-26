use strict;
use warnings;
use Test::More tests => 3;

BEGIN { use_ok 'Catalyst::Test', 'RetreatCenter' }
BEGIN { use_ok 'RetreatCenter::Controller::Persons' }

ok( request('/persons')->is_success, 'Request should succeed' );


