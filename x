#!/bin/sh
if [ -e "stop" ]
then
    stop
fi
if [ `whoami` = 'sahadev' ]
then
    export DBI_DSN="dbi:mysql:reg2"
else
    export DBI_DSN="dbi:SQLite:retreatcenter.db"
fi
script/retreatcenter_server.pl >cat.out 2>&1 &
