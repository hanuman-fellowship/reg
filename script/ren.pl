#!/usr/bin/env perl

# first do this:
# alter table program add column req_pay default '' not null;
# update program set req_pay = 'yes' where school_id >= 2;
# update string set the_key = 'payment_request_signed' where the_key = 'mmi_payment_request_signed'
# update string set the_key = 'payment_request_from' where the_key = 'mmi_payment_request_from'
# new strings req_mmc_dir, req_mmc_dir_paid
#
# run this file
# verify
# then can delete the table req_mmi_payment
#
use strict;
use warnings;
use DBI;
my $dbh = DBI->connect(undef, "sahadev", "JonB");
$dbh->do("drop table if exists req_payment");
my $sth = $dbh->do(<<'EOS');
create table req_payment (
    id integer primary key autoincrement,
    org        text          not null default 'mmi',
    person_id  integer       not null default 0,
    amount     integer       not null default 0,
    for_what   integer       not null default 0,
    the_date   text          not null default '',
    reg_id     integer       not null default 0,
    note       text          not null default '',
    code       text          not null default''
);
EOS
my $get_sth = $dbh->prepare("select * from req_mmi_payment");
my $ins_sth = $dbh->prepare(<<'EOS');
insert into req_payment (
    id, org, person_id, amount, for_what, the_date, reg_id, note, code
)
values (
    ?, 'MMI', ?, ?, ?, ?, ?, ?, ?
)
EOS
$get_sth->execute();
while (my $href = $get_sth->fetchrow_hashref()) {
    $ins_sth->execute(@{$href}{qw/
        id person_id amount for_what the_date reg_id note code
    /});
}

