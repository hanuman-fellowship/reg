#
# more tests please!
# lots of em!
#
use strict;
use warnings;
use Test::More 'no_plan';

use Date::Simple qw/:all/;

my ($d, $e);

$d = Date::Simple->new("20070902");
is($d->year(),  2007, "d8 year");
is($d->month(), 9,    "d8 month");
is($d->day(),   2,    "d8 day");

$d = Date::Simple->new("090207");
is($d->year(),  2007, "d6 year");
is($d->month(), 9,    "d6 month");
is($d->day(),   2,    "d6 day");

$d = Date::Simple->new("07/03/04");
is($d->year(),  2004, "flex year American default");
is($d->month(), 7,    "flex month American default");
is($d->day(),   3,    "flex day American default");

Date::Simple->european();
$d = Date::Simple->new("07/03/04");
is($d->year(),  2004, "flex year European");
is($d->month(), 3,    "flex month European");
is($d->day(),   7,    "flex day European");

Date::Simple->american();   # back to American for the rest of the tests
$d = Date::Simple->new("07/03/04");
is($d->year(),  2004, "flex year American");
is($d->month(), 7,    "flex d8 month American");
is($d->day(),   3,    "flex d8 day American");

$d = Date::Simple->new("20070902");
is("$d", "2007-09-02", "default format");
is($d->format("%A"), "Sunday", "format %A");

$d = Date::Simple->new("09/02/7", "%B %A");
is("date is $d", "date is September Sunday", "format override");

$d = Date::Simple->new("09/02/7");
$d->set_format("%B %A");
is("date is $d", "date is September Sunday", "format setting");
is($d->get_format(), "%B %A", "format getting");

$d = Date::Simple->new();
is("$d", today()->format(), "new() == today()");

$d = Date::Simple->new([ 2007, 9, 2]);
$e = Date::Simple->new(2007, 9, 2);
is("$d", "$e", "array_ref or list");

ok(date([ 2007, 9, 2]) == ymd(2007, 9, 2), "array_ref == date()");

ok(date("2/3/7") eq "2/3/2007", "compare a date object to a stringdate");
ok(date("2/3/1997") eq "2.3.97", "compare a date object to a stringdate");
ok(date("2/3/7") == "2/3/2007", "compare a date object to a stringdate");
ok(date("2/3/7") != "2/4/2007", "compare a date object to a stringdate");

$d = date(2007, 10, 2);
$e = $d - 4;
# 2, 1, 30, 29, 28
# 0  1   2   3   4
ok($e->month() == 9 && $e->day() == 28, "ndays before a date");

is(date("20071002") - date("20070928"), 4, "days between dates");

Date::Simple->default_format("%B %A");
$d = date("20070902");
is("$d", "September Sunday", "new default format");

$d = today("%B %A");
is("$d", $d->format("%B") . " " . $d->format("%A"),
         "today() new default format");

$d = date('');
is($d, undef, "'' gives undef?");

$d = date("-1");
is($d, today() -1, "days before");
$d = date("+4");
is($d, today()+4, "days after");
Date::Simple->relative_date(date("9/2/2007"));
$d = date("-3");
is($d, date("8/30/2007"), "relative days before");
#Date::Simple->relative_date(date("9/2/2007"));
$d = date("+5");
is($d, date("9/7/2007"), "relative days after");
$d = date('e');
is($d, date("12/31/2999"), "end of time");
