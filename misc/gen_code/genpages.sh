#!/bin/sh
clear
cd /v/reg/web
rm -f *.html regtable             # > debug.out 2>&1
echo "Generating web pages ..."
./gen 	                          # >>debug.out 2>&1
if [ ! -f $HOME/.netrc ]
then
	cp netrc $HOME/.netrc
	chmod 600 $HOME/.netrc
fi
echo "Transfering them to www.mountmadonna.org ..."
ftp www.mountmadonna.org <<EOF 	  # >>debug.out 2>&1
hash
prompt
cd www
mkdir staging
cd staging
mkdir pics
mdel *.html
del regtable
mput *.html
put regtable
EOF
clear
