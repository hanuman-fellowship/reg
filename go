#!/bin/sh
if [ `whoami` = 'sahadev' ]
then
    export DBI_DSN="dbi:mysql:reg2"
else
    export DBI_DSN="dbi:SQLite:retreatcenter.db"
fi
if [ $# = 0 ]
then
    nohup script/retreatcenter_server.pl &
    tail -f nohup.out
else
    script/retreatcenter_server.pl
fi
