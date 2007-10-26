use strict;
use warnings;
use Test::More tests => 3;

BEGIN { use_ok 'Catalyst::Test', 'RetreatCenter' }
BEGIN { use_ok 'RetreatCenter::Controller::Affiliations' }

ok( request('/affiliations')->is_success, 'Request should succeed' );


