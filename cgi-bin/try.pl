#!/usr/bin/perl
use strict;
use warnings;
use CGI;
my $q = CGI->new();
print $q->header(), "hello <b>world</b>!";
