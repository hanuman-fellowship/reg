#!/bin/sh
export DBIC_TRACE=1
if [ `whoami` = 'sahadev' ]
then
    export DBI_DSN="dbi:mysql:reg2"
else
    export DBI_DSN="dbi:SQLite:retreatcenter.db"
fi
if [ $# = 0 ]
then
    script/retreatcenter_server.pl >cat.out 2>&1 &
else
    script/retreatcenter_server.pl
fi
