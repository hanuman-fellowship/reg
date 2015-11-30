#!/usr/local/bin/perl
use strict;
use warnings;
use Test::More tests => 3;
use Util qw/
    phone_match
/;

ok(phone_match('', '', '1231231234',
               '1231231234', '', ''), "2 matches 3");
ok(phone_match('123', '', '',
               '', '123', ''), "0 matches 4");
ok(!phone_match('1', '2', '3',
                '4', '5', '6'), "none match");
