#!/bin/sh
export DBI_DSN="dbi:mysql:reg2"
script/retreatcenter_server.pl >cat.out 2>&1 &
