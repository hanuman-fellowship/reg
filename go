#!/bin/sh
export DBI_DSN="dbi:mysql:reg2"
sudo script/rc_server.pl -p 80 >output/server.out 2>&1
