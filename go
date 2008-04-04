#!/bin/sh
if [ `whoami` = 'jonbjornstad' ]
then
    export DBI_DSN="dbi:SQLite:retreatcenter.db"
else
    export DBI_DSN="dbi:mysql:reg2"
fi
if [ $# = 0 ]
then
    nohup script/retreatcenter_server.pl &
    tail -f nohup.out
else
    script/retreatcenter_server.pl
fi
