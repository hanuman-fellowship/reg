#!/bin/sh
if [ `whoami` = 'jonbjornstad' ]
then
export DBI_DSN="dbi:SQLite:retreatcenter.db"
else
export DBI_DSN="dbi:mysql:reg2"
fi
nohup script/retreatcenter_server.pl &
