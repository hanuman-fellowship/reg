#!/bin/sh
export DBI_DSN="dbi:mysql:reg3"
export PERL5LIB=.:$PERL5LIB
script/db_init jon@suecenter.org
