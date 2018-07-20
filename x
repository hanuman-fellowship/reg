#!/bin/sh
if [ `whoami` = 'sahadev' ]
then
    export DBI_DSN="dbi:mysql:reg2"
else
    export DBI_DSN="dbi:SQLite:retreatcenter.db"
    #export DBI_DSN="dbi:SQLite:regsq.db"
fi
script/retreatcenter_server.pl
