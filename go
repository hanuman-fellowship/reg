#!/bin/sh
if [ `whoami` = 'sahadev' ]
then
    export DBI_DSN="dbi:mysql:reg2"
else
    export DBI_DSN="dbi:SQLite:retreatcenter.db"
fi
if [ $# = 0 ]
then
    script/retreatcenter_server.pl >output/cat.out 2>&1 &
else
    script/retreatcenter_server.pl
fi
