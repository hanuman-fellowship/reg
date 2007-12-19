use strict;
use warnings;
package RetreatCenter::Controller::Program;
use base 'Catalyst::Controller';

use Util qw/
    leader_table
    affil_table
    slurp 
    monthyear
/;

use Date::Simple qw/date/;

use lib '../../';       # so you can do a perl -c here.

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub create : Local {
    my ($self, $c) = @_;

    # set defaults
    $c->stash->{check_kayakalpa}     = "checked";
    $c->stash->{check_retreat}       = "";
    $c->stash->{check_sbath}         = "checked";
    $c->stash->{check_quad}          = "";
    $c->stash->{check_collect_total} = "";
    $c->stash->{check_economy}       = "";
    $c->stash->{check_webready}      = "checked";
    $c->stash->{check_linked}        = "checked";
    $c->stash->{program_leaders}     = [];
    $c->stash->{program_affils}      = [];
    $c->stash->{program}             = {
        tuition      => 0,
        extradays    => 0,
        full_tuition => 0,
        deposit      => 100,
        canpol       => { name => "MMC" },      # a clever way to set default!
        housecost    => { name => "Default" },  # fake an object!
    };
    $c->stash->{canpol_opts} = [ $c->model("RetreatCenterDB::CanPol")->search(
        undef,
        { order_by => 'name' },
    ) ];
    $c->stash->{housecost_opts} =
        [ $c->model("RetreatCenterDB::HouseCost")->search(
            undef,
            { order_by => 'name' },
        ) ];
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "program/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    # dates are either blank or converted to d8 format
    my @mess;
    for my $d (qw/ sdate edate /) {
        my $fld = $c->request->params->{$d};
        if (! $fld =~ /\S/) {
            push @mess, "missing date field";
            next;
        }
        my $dt = date($fld);
        if ($fld && ! $dt) {
            # tell them which date field is wrong???
            push @mess, "Invalid date: $fld";
            next;
        }
        $c->request->params->{$d} = $dt? $dt->as_d8()
                                   :     "";
    }
    if (!@mess && $c->request->params->{sdate}
                  > 
                  $c->request->params->{edate}
    ) {
        push @mess, "end date must be after the start date";
    }
    if (! $c->request->params->{title} =~ /\S/) {
        push @mess, "title cannot be blank";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "program/error.tt2";
        return;
    }

    my %hash;
    for my $w (qw/
        name title subtitle glnum housecost_id
        retreat sdate edate tuition confnote
        url webdesc brdesc webready image
        kayakalpa canpol_id extradays full_tuition deposit
        collect_total linked ptemplate sbath quad
        economy footnotes
        school level phone email
    /) {
        $hash{$w} = $c->request->params->{$w};
    }
    my $p = $c->model("RetreatCenterDB::Program")->create({
        %hash,
    });
    my $id = $p->id();
    $c->response->redirect($c->uri_for("/program/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->stash->{program}
        = $c->model("RetreatCenterDB::Program")->find($id);
    for my $w (qw/ sdate edate /) {
        $c->stash->{$w} = date($p->$w) || "";
    }
    for my $w (qw/ webdesc brdesc confnote /) {
        my $s = $p->$w();
        $s =~ s{\r?\n}{<br>\n}g if $s;
        $c->stash->{$w} = $s;
    }
    my $l = join("<br>\n",
                 sort
                 map  { $_->person->last() . ", " . $_->person->first() }
                 $p->leaders()
                );
    $l .= "<br>" if $l;
    $c->stash->{leaders} = $l;

    my $a = join("<br>\n",
                 map { $_->descrip() }
                 $p->affils()
                );
    $a .= "<br>" if $a;
    $c->stash->{affils} = $a;

    $c->stash->{template} = "program/view.tt2";
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{programs} = [
        $c->model('RetreatCenterDB::Program')->search(
            undef,
            { order_by => 'title' },
        )
    ];
    $c->stash->{template} = "program/list.tt2";
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->model('RetreatCenterDB::Program')->find($id);
    $c->stash->{program} = $p;
    for my $w (qw/
        sbath collect_total kayakalpa retreat
        economy webready quad linked
    /) {
        $c->stash->{"check_$w"}  = ($p->$w)? "checked": "";
    }
    for my $w (qw/ sdate edate /) {
        $c->stash->{$w} = date($p->$w) || "";
    }

    # get all cancellation policies
    $c->stash->{canpol_opts} = [ $c->model("RetreatCenterDB::CanPol")->search(
        undef,
        { order_by => 'name' },
    ) ];
    # and housing costs
    $c->stash->{housecost_opts} =
        [ $c->model("RetreatCenterDB::HouseCost")->search(
            undef,
            { order_by => 'name' },
        ) ];

    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "program/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    # dates are either blank or converted to d8 format
    my @mess;
    for my $d (qw/ sdate edate /) {
        my $fld = $c->request->params->{$d};
        if (! $fld =~ /\S/) {
            push @mess, "missing date field";
            next;
        }
        my $dt = date($fld);
        if ($fld && ! $dt) {
            # tell them which date field is wrong???
            push @mess, "Invalid date: $fld";
            next;
        }
        $c->request->params->{$d} = $dt? $dt->as_d8()
                                   :     "";
    }
    if (!@mess && $c->request->params->{sdate}
                  > 
                  $c->request->params->{edate}
    ) {
        push @mess, "end date must be after the start date";
    }
    if (! $c->request->params->{title} =~ /\S/) {
        push @mess, "title cannot be blank";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        # ??? person or program or a general error template?
        $c->stash->{template} = "person/error.tt2";
        return;
    }

    my %hash;
    # ??? ask DBIx for this list?
    # ??? put at top for use here and in update_do?
    for my $w (qw/
        name title subtitle glnum housecost_id
        retreat sdate edate tuition confnote
        url webdesc brdesc webready image
        kayakalpa canpol_id extradays full_tuition deposit
        collect_total linked ptemplate sbath quad
        economy footnotes
        school level phone email
    /) {
        my $v = $c->request->params->{$w};
        $hash{$w} = ($w =~ m{date})? (date($v) || "")
                   :                 $v;
    }
    my $p = $c->model("RetreatCenterDB::Program")->find($id);
    $p->update(\%hash);
    $c->response->redirect($c->uri_for("/program/view/" . $p->id));
}

sub leader_update : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->stash->{program}
        = $c->model("RetreatCenterDB::Program")->find($id);
    $c->stash->{leader_table} = leader_table($c, $p->leaders());
    $c->stash->{template} = "program/leader_update.tt2";
}

sub leader_update_do : Local {
    my ($self, $c, $id) = @_;

    my @cur_leaders = grep {  s{^lead(\d+)}{$1}  }
                      keys %{$c->request->params};
    # delete all old leaders and create the new ones.
    $c->model("RetreatCenterDB::LeaderProgram")->search(
        { p_id => $id },
    )->delete();
    for my $cl (@cur_leaders) {
        $c->model("RetreatCenterDB::LeaderProgram")->create({
            l_id => $cl,
            p_id => $id,
        });
    }
    # show the program again - with the updated leaders
    view($self, $c, $id);
    $c->forward('view');
}

sub affil_update : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->stash->{program}
        = $c->model("RetreatCenterDB::Program")->find($id);
    $c->stash->{affil_table} = affil_table($c, $p->affils());
    $c->stash->{template} = "program/affil_update.tt2";
}

sub affil_update_do : Local {
    my ($self, $c, $id) = @_;

    my @cur_affils = grep {  s{^aff(\d+)}{$1}  }
                     keys %{$c->request->params};
    # delete all old affils and create the new ones.
    $c->model("RetreatCenterDB::AffilProgram")->search(
        { p_id => $id },
    )->delete();
    for my $ca (@cur_affils) {
        $c->model("RetreatCenterDB::AffilProgram")->create({
            a_id => $ca,
            p_id => $id,
        });
    }
    # show the program again - with the updated affils
    view($self, $c, $id);
    $c->forward('view');
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    # explain this choice - see Person.pm.
    $c->model('RetreatCenterDB::Program')->search(
        { id => $id }
    )->delete();
    $c->model('RetreatCenterDB::AffilProgram')->search(
        { p_id => $id }
    )->delete();
    # ??? LeaderProgram, too.
    $c->response->redirect($c->uri_for('/program/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;

__END__
sub publish : Local {
    my ($self, $c) = @_;

# temporary... what is the Cwd?
open my $test, ">", "touchfile";
print {$test} "hi\n";
close $test;
return;
    # 
    # generate each of the program pages
    #
    my $tag_regexp = '<!--\s*T\s+(\w+)\s*-->';
    for my $p (Gen::Program->programs) {
        print $p->fname, "\n";
        open OUT, ">".$p->fname
            or die "cannot open ", $p->fname, ": $!\n";
        my $copy = $p->template;
        $copy =~ s/$tag_regexp/
            except($p->pname, $1) || $p->$1()
        /xge;
        print OUT $copy;
        close OUT;
    }
}

1;

__END__

#
# generate the program and event calendars
#
my $events = "";
my $programs = "";

my $progRow     = slurp "progRow";
my $e_progRow   = slurp "e_progRow";
my $e_rentalRow = slurp "e_rentalRow";

my $cur_event_month = 0;
my $cur_prog_month = 0;
my ($rental);
for my $e (sort { $a->sdate <=> $b->sdate || $a->edate <=> $b->edate }
           grep { $_->linked } Program->programs, Rental->rentals) {
	$rental = ref $e eq "Rental";
	my $my = monthyear($e->sdate);
	if ($cur_event_month != $e->sdate->month) {
		$events .= "<tr><td class='event_my_row' colspan=2>$my</td></tr>\n";
		$cur_event_month = $e->sdate->month;
	}
	if (not $rental and $cur_prog_month != $e->sdate->month) {
		$programs .= "<tr><td class='prog_my_row' colspan=2>$my</td></tr>\n";
		$cur_prog_month = $e->sdate->month;
	}
	if ($rental) {
		my $copy = $e_rentalRow;
		$copy =~ s/$tag_regexp/
			except($e->rname, $1) || $e->$1()
		/xge;
		$events .= $copy;
	} else {
		my $copy = $e_progRow;
		$copy =~ s/$tag_regexp/
			except($e->pname, $1) || $e->$1()
		/xge;
		$events .= $copy;

		$copy = $progRow;
		$copy =~ s/$tag_regexp/
			except($e->pname, $1) || $e->$1()
		/xge;
		$programs .= $copy;
	}
}
#
# we have gathered all the info.
# now to insert it in the templates and output
# the .html files for the program and event lists.
#
my $s;
$s = slurp "events";
open OUT, ">events.html" or die "cannot open events.html: $!\n";
$s =~ s/<!--\s*T\s+eventlist.*-->/$events/;
print OUT $s;
close OUT;
$s = slurp "programs";
open OUT, ">programs.html" or die "cannot open programs.html: $!\n";
$s =~ s/<!--\s*T\s+programlist.*-->/$programs/;
print OUT $s;
close OUT;

#
# generate the regtable for online registration
#
open OUT, ">regtable"
	or die "cannot open regtable: $!\n";
for my $p (Program->programs) {
	my $ndays = ($p->edate - $p->sdate) || 1;	# personal retreats
	my $fulldays = $ndays + $p->extdays;

	#
	# prognum and pname should be first and second
	# for looking up purposes.
	#
	print OUT "prognum\t", $p->prognum, "\n";
	print OUT "pname\t", $p->pname, "\n";
	print OUT "desc\t", except($p->pname, "subtitle") || $p->desc, "\n";
	print OUT "dates\t", $p->dates, "\n";
	print OUT "edate\t", $p->edate->as_d8, "\n";
	print OUT "leaders\t", $p->leaders, "\n";
	print OUT "footnotes\t", $p->footnotes, "\n";
	print OUT "ndays\t$ndays\n";
	print OUT "fulldays\t$fulldays\n";
	print OUT "deposit\t", $p->deposit, "\n";
	print OUT "colltot\t", $p->colltot, "\n";
	my $pol = $p->cancellation_policy();
	$pol =~ s/\n/NEWLINE/g;
	print OUT "canpol\t$pol\n";

	my $housing = $p->housing;
	my $tuition = $p->tuition;
	my $full_tuition = $p->fulltuit;
	my $month = $p->sdate->month;

	for my $t (Housing->types) {
		next if $t =~ /unknown/;
		next if $t =~ /quad/ and not $p->quad;
		next if $t =~ /econ/ and not $p->econ;
		next if $t =~ /single bath/ and not $p->sbath;
        next if $t =~ /center tent/
			and not ($p->pname eq "PERSONAL RETREATS" or
					 $p->pname =~ /tnt/i or
					 (5 <= $month and $month <= 10));
		next if $t =~ /triple|dorm/ and $p->pname eq "PERSONAL RETREATS";

		my $cost = Housing->cost($housing, $t);
		next unless $cost;	# if zero - this type of housing is not offered!
		my $hcost;
		if (1 <= $housing and $housing <= 5) {
			$hcost = $cost;
		}
		else {
			$hcost = $cost*$ndays;
			$hcost -= 0.10*$hcost if $fulldays >= 7;
			$hcost -= 0.10*$hcost if $fulldays >= 30;
			$hcost = int($hcost);
		}
		print OUT "basic $t\t",
				  $hcost + $tuition,
				  "\n";
		if ($p->extdays) {
			# and discount 10%, 10%
			my $hcost = $cost*$fulldays;		# what if 1 <= $housing <= 5???
			$hcost -= 0.10*$hcost if $fulldays >= 7;
			$hcost -= 0.10*$hcost if $fulldays >= 30;
			$hcost = int($hcost);
			print OUT "full $t\t", $hcost + $full_tuition, "\n";
		}
	}
}
close OUT;
#
# clear the tmp files
#
#unlink <*.tmp>;

#
# take the document below and place it in cms_mmc.html
# like an advanced POD.   It's best to have the documentation
# IN the source file so it can't be lost!
#
open DOC, ">cms_mmc.html" or die "cannot open cms_mmc.html: $!\n";
while (<DATA>) {
	print DOC;
}
close DOC;

__DATA__
<html>
<head>
<title>CMS for MMC</title>
<style type="text/css">
h1 {
	color: red;
	font-size: 30pt;
}
h2 {
	color: green;
	font-size: 26pt;
}
h3 {
	color: blue;
}
.path {
	color: purple;
	font-size: 13pt;
	font-weight: bold;
	font-family: courier;
}
.emphasize {
	color: orange;
	font-size: 15pt;
	font-weight: bold;
	font-style: italic;
}
</style>
</head>
<body><table width=700><tr><td>
<h1><center>A Content Management System<br>for<br>Mount Madonna Center</center></h1>
A "content management system" is used, for example, by a newspaper
to manage the content of their website.  A journalist can submit
the text of their story with some specialized software and
it will be processed and will be routed magically here and there
and will eventually appear on the web site.
Other sources of news will appear there
as well perhaps taking a different route.
The journalists do not need to know how the web site is organized
or have any knowledge of the web languages HTML or CSS.
<p>
In a similiar way, by using this system the registar of programs
at Mount Madonna can enter information about upcoming programs
and rentals in a normal way (if you want to call 'reg' normal, that is) and
that information will, after a good deal of processing,
appear on the website in a consistent and standard way.
People all over the world can immediately begin registering online.
<p>
This document can be found at
<a href="http://www.mountmadonna.org/staging/cms_mmc.html">http://www.mountmadonna.org/staging/cms_mmc.html</a>.
<p>
<a href="#dataflow">Process and Data Flow</a><br>
<a href="#input">Input</a><br>
<a href="#leaders">Leaders</a><br>
<a href="#housing">Housing Costs</a><br>
<a href="#rentals">Rentals</a><br>
<a href="#programs">Programs</a><br>
<a href="#full">Full Programs</a><br>
<a href="#template">Template Files and Tags</a><br>
<a href="#config">Configuration Files</a><br>
<a href="#style">Style Sheet</a><br>
<a href="#footnotes">Footnotes</a><br>
<a href="#shorthand">Shorthand</a><br>
<a href="#publication">Publication</a><br>
<a href="#brochure">Brochure</a><br>
<a href="#transfer">Transfer</a><br>
<a href="#perl">Perl, Javascript and Shell Scripts</a><br>
<a name=dataflow>
<h2>Process and Data Flow</h2>
Here are 3 pictures of the processes and the flow of data within the system.
<p>
<img src=pics/flow1.gif><p>
<img src=pics/flow2.gif><p>
<img src=pics/flow3.gif><p>
<a name=input>
<h2>Input</h2>
There are 4 places in 'reg' where information has to be entered:
<ul>
<li>Leaders
<li>Housing Costs
<li>Rentals
<li>Programs
</ul>
This information needs to be entered quite precisely.
Any errors will be quickly propogated to the entire world.<br>
<i>Pay attention</i> especially to dollar amounts and email addresses.
<p>
There are also <a href=#template>templates</a>,
<a href=#config>two configuration files</a>,
and a <a href=#style>style sheet</a>
that need to be adjusted.
<p>
This is a lot.  This is a 'front-loaded' process.
You do a lot of work up front and then things become very easy.
After the initial configuration and setup most of the effort
will be in entering new programs and new rentals.
The other inputs should be fairly stable and rarely in need of change.
<a name=leaders>
<h3>Leaders</h3>
From the top menu choose 'T' for 'The Leaders'.
<p>
For each leader of a program enter these attributes:
<p>
<table width=700 border=1 cellpadding=5>
<tr><td width=170>First Name</td><td>required</td></tr>
<tr><td>Last Name</td><td>required</td></tr>
<tr><td>Street</td><td>2 fields</td></tr>
<tr><td>City</td><td>&nbsp;</td></tr>
<tr><td>State</td><td>&nbsp;</td></tr>
<tr><td>Zip</td><td>&nbsp;</td></tr>
<tr><td>Private?</td><td>Is their address and phone number information private and not to be distributed?</td></tr>
<tr><td>Phones</td><td>A long text field for a variety of
phone numbers.</td></tr>
<tr><td>Public Email</td><td>Public - meaning okay to share.</td></tr>
<tr><td>Private Email</td><td>Do not share this with anyone.</td></tr>
<tr><td>Website</td><td>A website related to the program they're giving. No need for the "http://" prefix.</td></tr>
<tr><td>Image</td><td>The filename of a picture of the person (hopefully recent).
<p>
This picture should have been resized to have a width of
approximately 170 pixels.
There can be a larger version as well and its name should
be the same as the smaller one but with a "b-" prefix.
If you enter a filename here in the Leader screen it will be checked
that it actually exists - it should live on the Unix machine
in this directory:
<blockquote>
<span class=path>/v/reg/web/pics/</span>
</blockquote>
</td></tr>
<tr><td>Comment</td><td>Two lines of arbitrary comments.</td></tr>
</table>
<p>
The only required fields are First and Last names.
These fields are <b>not</b> actually used on the web site:
Street, City, State, Zip, Private?, Phones, Private Email, Comment.
<p>
You can also enter a short biography of the person.
Press 'G' to bring up the bioGraphy screen.
Here you have 4 additional commands:
<p>
<table border=1 cellpadding=5>
<tr><td>Edit</td><td>Add/Edit the text of the biography.</td></tr>
<tr><td>Append</td><td>Append FROM a text file.</td></tr>
<tr><td>eXport</td><td>Export the biography TO a text file.</td></tr>
<tr><td>Clear</td><td>Clear the text entirely so you can start over.</td></tr>
</table>
<p>
The last 3 will likely be rarely used.
<p>
See <a href=#shorthand>Shorthand</a> for a way of doing italics, bold, and hrefs
within the text. Paragraphs and lists, too. 
<a name=housing>
<h3>Housing Costs</h3>
</a>
From the top menu choose 'M' for 'Maintenance' and then '1'
for 'Housing Costs'.
<p>
This brings up a table of costs for the different types
of housing.  The first "Per Day" column is for normal costs.
Note that the "Single Bath" and "Double Bath" costs are
<b>in addition</b> to the cost of a "Single" and "Double".
It is not the total cost of the room with a bath.
<p>
The 6 "Total Cost" columns are for programs for which there
is a fixed total cost - not on a per day basis.  This is rarely used.
<p>
The 2 "Per Day" columns at the far right are for programs
that have special per day costs.
<p>
The "Housing Cost" field in the Program screen references this
table.  0 is for the normal per day cost.  1-8 are for 
the other columns.
<a name=rentals>
<h3>Rentals</h3>
From the top menu choose 'G' for 'Group Rentals'.
<p>
For each rental (do ALL rentals want to appear on the website?)
enter these attributes:
<p>
<table width=700 border=1 cellpadding=5>
<tr><td width=170>Rental Name</td><td>To identify the rental - used
for searching purposes.  
<tr><td>Start Date</td><td>Press F5 for a nifty calendar.</td></tr>
<tr><td>End Date</td><td>F5 for a calendar.
After entering the dates you will see the days of the week to the
right of the dates as a way of verifying that you entered the
dates correctly.</td></tr>
<tr><td>GL Number</td><td>This field is computed automatically and
you are given the option to change it in case it's not right.
Only the accounting people know.</td></tr>
<tr><td>Linked?</td><td>Should this event be included in the online event list?</td></tr>
<tr><td>Title</td><td>A catchy phrase to name the event or the group.</td></tr>
<tr><td>SubTitle</td><td>Sometimes the title is the name of the group
presenting this rental and the subtitle is a short summary of what
the event is about.</td></tr>
<tr><td>Phone</td><td>&nbsp;</td></tr>
<tr><td>Website</td><td>&nbsp;</td></tr>
<tr><td>Email</td><td>&nbsp;</td></tr>
<tr><td>Description</td><td>As many lines as you would like
to describe the rental event.</td></tr>
</table>
<p>
The last 5 fields give information about the rental.
They will each be put on separate lines.
Phone, website and email will have labels identifying them.
The appearance of each of the 5 can be controlled individually
with style sheets.
<a name=programs>
<h3>Programs</h3>
From the top menu choose 'P' for 'Programs'.
<p>
For each program enter these attributes:
<p>
<table width=700 border=1 cellpadding=5>
<tr><td width=170>Program Name</td><td>To identify the program - used
for searching purposes.
If you include 'TNT' in the program
name then it will allow the Center Tent housing option regardless of the season.</td></tr>
</td></tr>
<tr><td>Start Date</td><td>Press F5 for a nifty calendar.</td></tr>
<tr><td>End Date</td><td>F5 for a calendar.
After entering the dates you will see the days of the week to the
right of the dates as a way of verifying that you entered the
dates correctly.</td></tr>
<tr><td>Title</td><td>A short catchy phrase to name the event.</td></tr>
<tr><td>SubTitle</td><td>A little bit more elaboration on the Title.</td></tr>
<tr><td>Confirmation Letter Notes</td><td>Two fields of notes to append to every confirmation letter for this program.</td></tr>
<tr><td>Tuition</td><td>In dollars - be sure it's right!</td></tr>
<tr><td>Extra Days</td><td>If this program has two versions - basic and
full - how many extra days are there in the full version?
See <a href=#full>Full Programs</a> below.</td></tr>
<tr><td>Full Tuition</td><td>How much is the total tuition for the Full program?  This is not how much <i>more</i> but the total amount.</td></tr>
<tr><td>Online Deposit</td><td>How much deposit is collected when registering online?</td></tr>
<tr><td>Collect Total?</td><td>Should the entire cost of the program
be collected up front when registering online?
If you say 'Y' then the Online Deposit field is ignored.</td></tr>
<tr><td>Attachment</td><td>Put a 0 or 1 in this field.  0 means the
confirmation letter will have both a map to the center <i>and</i>
the Kaya Kalpa information.
1 means just the map - NOT Kaya Kalpa.
<p>
This will attach the file 
<span class='path'>/v/reg/lst/map0</span> or
<span class='path'>/v/reg/lst/map1</span>.
</td></tr>
<tr><td>Cancel Policy</td><td>Normally 0 this can be set to a
digit 1-9 for special cancellation policies to be used in the
confirmation letter.  The text of the policies is contained
in the file <span class='path'>/v/reg/lst/cancelX</span> for HTML email
and in <span class='path'>/v/reg/lst/tcancelX</span> for text email.
The X is a digit 0-9.
</td></tr>
<tr><td>Retreat?</td><td>Is this program a center retreat?  If 'Y' then some special costs apply and we offer Economy housing.</td></tr>
<tr><td>Housing Cost</td><td>A digit 0-9 to reference a cost of housing column.  See <a href=#housing>above</a> for details.</td></tr>
<tr><td>Single Bath?</td><td>Are singles with bath available for this program?</td></tr>
<tr><td>GL Number</td><td>This field is computed automatically and
you are given the option to change it in case it's not right.
Only the accounting people know.</td></tr>
<tr><td>Extra Web URL</td><td>A web address for this program.
This might be in addition to or instead of a URL for the leader.</td></tr>
<tr><td>Program Image</td><td>If there is no image for the leader(s) then
this picture filename will be used for the program.  As with
leader images the filename will be checked for existence in
the directory <span class='path'>/v/reg/web/pics/</span>.</td></tr>
<tr><td>Template</td><td>The default template file used to generate
the program web pages is:
<blockquote>
<span class='path'>/v/reg/web/templates/template.html</span>
</blockquote>
Rentals (like Open Gate Sangha)
for whom we are doing their registration will likely want
a different look to their page.
Such programs can have their own special template if you supply it here.
reg will verify its existence in:
<blockquote>
<span class='path'>/v/reg/web/templates/</span>
</blockquote>
<tr><td>Web Ready?</td><td>Is this program ready to have its webpage
made live?  Some programs (see the discussion of
<a href=#full>Full Programs</a> below) will not have a webpage.</td></tr>
<tr><td>Linked?</td><td>Should this program be linked to all
the others? Such programs will be independent and excluded
from the 'next program' button and the program
and event calendars.  This should be 'Y' for some rentals that we will be doing
the registration for will not want to be seen as a MMC sponsored event.
Like Open Gate Sangha.</td></tr>
<tr><td>Footnotes</td><td>The <a href=#footnotes>footnotes</a> can be * or **, +, and %.</td></tr>
<tr><td>Affiliation</td><td>What affiliations (in mlist) should be given to 
each person who registers for this program?  You can give up to 3.
The meaning of the affiliations you do give will be displayed
and you will need to confirm that that is what you want by typing
a capital 'Y'.  This is sort of awkward but serves to make
sure that you don't assign an incorrect affiliation!</td></tr>
</td></tr>
</table>
<p>
You will also need to add the leaders of the program.
Choose 'L' from the menu in the Program screen.
The existing leaders (which you added before as outlined above)
will be presented in a pick list.
If there is only one leader for the program leave the second one blank (duh!).
<p>
You then need to enter the full descriptions of the program.
From the top menu choose Program-Info-WebDesc-Edit and enter as long of
a description as you wish - this will go on the web page where
there is no limit.  Hit F8 to finish and then choose
Program-Info-bRDesc-Edit.  Enter a
shorter description that will fit in the limited space of the
printed brochure (which is SO last millenium).
Under the Other menu here is Append, Export,
Clear and Print which will likely be used rarely.
See <a href=#shorthand>Shorthand</a> for a way of doing italics, bold and hrefs
within the text of both descriptions.  Paragraphs and lists, too.
<a name='full'>
<h3>Full Programs</h3>
</a>
When you add a new program and mark Extra Days with something greater
than 0 it indicates that this program has two flavors - basic and full.
A second program is added for you automatically.
Its name is the same as the basic program but with
"&nbsp;FULL" appended - like "NISKER" and "NISKER FULL".
You don't need to worry about the attributes of this program.
They will be filled in for you from the basic program.
The full program will <b>not</b> have a separate web page.
Online registration for both programs will be taken care of
on the web page for the basic program.
<a name=template>
<h3>Template Files and Tags</h3>
</a>
For the initial setup
there are several template files that will
need to be edited and tweaked (but hopefully not endlessly) by the webmaster.
They all live in the directory
<span class=path>/v/reg/web/templates/</span>.
<p>
<table cellpadding=5 border=1>
<tr><td><span class=path>template.html</span></td><td>The default template
file for a program web page.</td></tr>
<tr><td><span class=path>ul_template.html</span></td><td>A template
file for an <i>unlinked</i> program web page.  Could be named anything.
This example has no prev/next buttons and also no little monthly calendar.
The name is placed in the template field on the program screen.  See
<a href=#programs>programs</a>.</td></tr>
<tr><td><span class=path>progRow.html</span></td><td>A row in the Programs Calendar.</td></tr>
<tr><td><span class=path>e_progRow.html</span></td><td>A row for a Program in the Events Calendar.</td></tr>
<tr><td><span class=path>e_rentalRow.html</span></td><td>A row for a Rental in the Events Calendar.</td></tr>
<tr><td><span class=path>events.html</span></td><td>The Events calendar.  It gives rise to events.html.</td></tr>
<tr><td><span class=path>programs.html</span></td><td>The Program Calendar. It gives rise to programs.html.</td></tr>
<tr><td><span class=path>popup.html</span></td><td>The small web page that contains the enlarged pictures of the leaders.</td></tr>
</table>
<p>
The text within these template files is normal HTML with one exception.
An HTML comment like this:
<blockquote>
&lt;!--T webdesc --&gt;
</blockquote>
will be replaced by information relevant to the current program.
Such special comments are also called 'tags'.
The string 'webdesc' above can come from this list of keywords:
<p>
<table width=700 cellpadding=5 border=1>
<tr><th align=left>Keyword</th><th align=left>Description</td></tr>
<tr><td>barnacles</td><td>These are the <a href=#footnotes>footnote</a> markers
from the end of the program description: * or **, +, and %.<br>
+ is translated to a dagger &dagger;,
and % becomes a section mark &sect;.</td</tr>
<tr><td>bigpic</td><td>This is used only in the popup.html template.
It is replaced by a link to popup a window with the larger version
of the leader's picture.</td</tr>
<tr><td>brdesc</td><td>The Brochure Description field for the program.</td</tr>
<tr><td>dates</td><td>Program dates in this form:
<blockquote>
June 3-5<br>
&nbsp;&nbsp;or<br>
June 23-July 10
</blockquote>
</td</tr>
<tr><td>dates_tr</td><td>Same as 'dates' but without the initial month
name and with any subsequent month name truncated to 3 letters.
<blockquote>
3-5<br>
&nbsp;&nbsp;or<br>
23-Jul 10
</blockquote>
</td</tr>
<tr><td>dates_tr2</td><td>Same as 'dates' but without the initial
month name.</td</tr>
<tr><td>email</td><td>Used for only for rentals (in e_rentalRow.html) this is
the email address (if any) to contact for information about the rental.</td</tr>
<tr><td>eventlist</td><td>This is the one tag that occurs in events.html.
It is the list of events (rentals and programs) in
chronological order.  It is generated using the templates e_rentalRow.html and
e_progRow.html.</td</tr>
<tr><td>fee_table</td><td>The fee table for the program.
There are various strings within it that come from
the configuration file <a href=#config>lookup.txt</a>.</td</tr>
<tr><td>firstprog_nextmonth</td><td>A link to the first program in the next month - relative to the current program.</td</tr>
<tr><td>firstprog_prevmonth</td><td>A link to the first program in the previous month - relative to the current program.</td</tr>
<tr><td>fname</td><td>The filename (not the complete pathname - just the filename) of the generated HTML file for this program.  It is the first 3 letters of the program name plus day and month of the start date.  Like this: AND-6-9.html</td</tr>
<tr><td>leader_bio</td><td>The leader's biography.  It is the biography 
plus their email and website if present.  If there are two leaders the second
comes after the first.
</td</tr>
<tr><td>leaders</td><td>The leader's names.</td</tr>
<tr><td>month_calendar</td><td>A short version of the programs happening
in the same month as the current program.</td</tr>
<tr><td>nextprog</td><td>A link to the first program after the current
one.  It links to itself if it is the first one.</td</tr>
<tr><td>picture</td><td>The HTML fragment that displays the leader's pictures.
It includes a link to pop up a larger version of a picture if it is
available.  The HTML is generated using two keys (click_enlarge and
imgwidth) from the configuration file
<a href=#config>lookup.txt</a>.</td</tr>
<tr><td>prevprog</td><td>A link to the first program before the current
one.  It links to itself if it is the first one.</td></tr>
<tr><td>phone</td><td>Used for only for rentals (in e_rentalRow.html) this is
the phone number (if any) to contact for information about the rental.</td</tr>
<tr><td>prognum</td><td>The program number.  It is sequentially assigned
and references 'regtable'.</td</tr>
<tr><td>programlist</td><td>This is the one tag that occurs in programs.html.
It is the list of programs (not rentals) in
chronological order.  It is generated using the template progRow.html</td></tr>
<tr><td>subtitle</td><td>The subtitle of the current program/rental. See title below.</td</tr>
<tr><td>title</td><td>The title of the current program/rental. 
If there are leaders assigned to a program (which is normal)
the title becomes the leader names and the subtitle becomes "title - subtitle"
which is essentially the "Description" field on the program screen.
Confusing, huh?  Yes, but that IS the way that has evolved for doing this.
AND the barnacles are not included here even though they
occur at the end of the Description field.
</td</tr>
<tr><td>webdesc</td><td>The Web Description field for the program.</td</tr>
<tr><td>webdesc_plus</td><td>Same as webdesc but with any footnotes
expanded and appended to the description.
They are expanded using the configuration
file <a href=#config>lookup.txt</a></td</tr>
<tr><td>weburl</td><td>The website (if any) for the program preceded by
a label from 
<a href=#config>lookup.txt</a></td</tr>
<tr><td>website</td><td>The website (if any) for the rental preceded by
a label from 
<a href=#config>lookup.txt</a></td</tr>
</td</tr>
</table>

<a name=config>
<h3>Configuration Files</h3>
</a>
In <span class=path>/v/reg/web/config/lookup.txt</span> we have
a lookup table.  It is used by the script for various strings in
web pages.
The format of each line in the file is "name", tab, "value".
 You can edit this file to change the values but do not change the names.
<p>
<table cellpadding=5 border=1>
<tr><th align=left>Name</th><th align=left>Current value</th></tr>
<tr><td>heading</td><td>Total Cost Per Person&lt;br&gt;(including tuition, meals, lodging, and facilities use)</td></tr>
<tr><td>typehdr</td><td>Housing Type</td></tr>
<tr><td>costhdr</td><td>Cost</td></tr>
<tr><td>commuting</td><td>Commuting (Day use, meals &amp; facilities)</td></tr>
<tr><td>own tent</td><td>Your Tent</td></tr>
<tr><td>own van</td><td>Your Van</td></tr>
<tr><td>center tent</td><td>Mount Madonna Center Tent</td></tr>
<tr><td>dormitory</td><td>Dormitory (4-7 to a room or cabin)</td></tr>
<tr><td>economy</td><td>Economy (10 or more to a room)</td></tr>
<tr><td>triple</td><td>Triple (3 to a room or cabin)</td></tr>
<tr><td>double</td><td>Double (2 to a room or cabin)</td></tr>
<tr><td>double</td><td>bath Double with Bath (2 to a room)</td></tr>
<tr><td>single</td><td>Single (1 to a room or cabin)</td></tr>
<tr><td>single bath</td><td>Single with Bath (1 to a room)</td></tr>
<tr><td>*</td><td>Continuing Education Credit for nurses.</td></tr>
<tr><td>**</td><td>Continuing Education Credit for nurses, LMFT's, and LCSW's.</td></tr>
<tr><td>+</td><td>Fulfills the spiritual practice prerequisite for John F. Kennedy University's Graduate School for Holistic Studies.</td></tr>
<tr><td>%</td><td>An elective for YTT 500.</td></tr>
<tr><td>weburl</td><td>For more information see</td></tr>
<tr><td>email1</td><td>You can contact</td></tr>
<tr><td>email2</td><td>at</td></tr>
<tr><td>imgwidth</td><td>170 (this is the width of the images of the leaders)</td></tr>
<tr><td>click_enlarge</td><td>(click to enlarge)</td></tr>
<tr><td>email</td><td>Email</td></tr>
<tr><td>phone</td><td>Phone</td></tr>
<tr><td>website</td><td>Website</td></tr>
</table>
<p>
In <span class=path>/v/reg/web/config/exceptions.txt</span> we have
another kind of configuration file.
Its format is 3 columns separated by tabs: "name", "tag", and "value".
The name is either a program name or a rental name.
The tag is from the list of tags in the table above in the
<a href=#template>template file and tags</a> section.
It is used for making exceptions to the normal mechanism.
For example:
<blockquote>
NISKER&nbsp;&nbsp;&nbsp;dates&nbsp;&nbsp;&nbsp;3-5, 7-10, 12-15
</blockquote>
Now when the program named NISKER needs to display its dates
it will use "3-5, 7-10, 12-15" instead.
<p>
If the value of an exception is a multi-line value
you can put the lines in a file and then use this format:
<blockquote>
NISKER&nbsp;&nbsp;&nbsp;fee_table&nbsp;&nbsp;&nbsp;file config/niskerfees.txt
</blockquote>
<p>
In the exceptions.txt file blank lines are ignored as
are lines beginning with '#'.

<a name=style>
<h3>Style Sheet</h3>
</a>
To control the appearance of the generated web pages
and event/program listing there are style sheet class names.
Some of them occur in templates (where they can be changed) and
some are generated by a script (where they can't).
It is nice to keep all style sheets in one place -
<span class=path>www.mountmadonna.org/www/mmc.css</span>.
<br>These class names are used:
<p>
<table cellpadding=5 border=1>
<tr><th align=left>Class Name</th><th align=left>Description</th><th align=left>Where</th></tr>
<tr><td>click_enlarge</td><td>text underneath a picture that
can be enlarged</td><td>Script</td></tr>
<tr><td>caltable</td><td>the table tag for the little month calendar</td><td>Script</td></tr>
<tr><td>monthyear</td><td>the month/year heading for the little month calendar</td><td>Script</td></tr>
<tr><td>dates_tr</td><td>the truncated dates on the left of the little month calendar</td><td>Script</td></tr>
<tr><td>title</td><td>the title of a program in the little month calendar</td><td>Script</td></tr>
<tr><td>subtitle</td><td>the subtitle of a program in the little month calendar</td><td>Script</td></tr>
<tr><td>event_my_row</td><td>the month/year line in the event listing</td><td>Script</td></tr>
<tr><td>prog_my_row</td><td>the month/year in the program listing</td><td>Script</td></tr>
<tr><td>event_phone</td><td>the phone number line in an event listing</td><td>Script</td></tr>
<tr><td>event_website</td><td>the website line in an event listing</td><td>Script</td></tr>
<tr><td>event_email</td><td>the email line in an event listing</td><td>Script</td></tr>
<tr><td>logo</td><td>the mmc logo in a program listing in the event listing</td><td>e_progRow.html</td></tr>
<tr><td>event_dates</td><td>the dates of a program or event in the event listing</td><td>e_progRow.html<br>e_rentalRow.html</td></tr>
<tr><td>event_title</td><td>the title of a program or event in the event listing</td><td>e_progRow.html<br>e_rentalRow.html</td></tr>
<tr><td>event_subtitle</td><td>the subtitle of a program or event in the event listing</td><td>e_progRow.html<br>script => e_rentalRow.html</td></tr>
<tr><td>event_desc</td><td>the description of an event in the event listing</td><td>script => e_rentalRow.html</td></tr>
<tr><td>prog_title</td><td>the title of a program in the program listing</td><td>progRow.html</td></tr>
<tr><td>prog_subtitle</td><td>the subtitle of a program in the program listing</td><td>progRow.html</td></tr>
<tr><td>barnacles</td><td>the footnote characters coming after the subtitle in the program listing</td><td>progRow.html</td></tr>
<tr><td>prog_dates</td><td>the dates of a program in the program listing</td><td>progRow.html</td></tr>
<tr><td>ptitle</td><td>the title of a program on the program pages</td><td>template.html</td></tr>
<tr><td>psubtitle</td><td>the subtitle of a program on the program pages</td><td>template.html</td></tr>
<tr><td>pdates</td><td>the dates of a program on the program pages</td><td>template.html</td></tr>
</table>

<a name=footnotes>
<h3>Footnotes</h3>
</a>
Footnotes are marked by appending * or **, +, and % to a program description.
In some contexts these 'barnacles' are preserved after the description.
On a program web page itself they are not.  Instead the webdesc_plus description
is extended by looking up the *, **, +, and % in the configuration file
lookup.txt and appending the expansion found there.

<a name=shorthand>
<h3>Shorthand</h3>
</a>
When editing the biography of a leader or the descriptions
of a program or rental you can use the following shorthand:
<hr>
<blockquote>
<pre>
This is _rather_ nifty and very *important*.
For more info please click %here%www.mountmadonna.org%.
You can contact me via mail me at ~diana@lala.com~.

New things to say and there's always more!

Three colors:
# red
# blue
# green

And several foods:
- tofu
- rice
- mango
- almonds
</pre>
</blockquote>
<hr>
to achieve this:
<hr>
<blockquote>
This is <i>rather</i> nifty and very <b>important</b>.
For more info please click <a href='http://www.mountmadonna.org' target='_blank'>here</a>.
You can contact me via mail me at <a href="mailto:diana@lala.com">diana@lala.com</a>.
<p>
New things to say and there's always more!
<p>
<ol>
<li>red
<li>blue
<li>green
</ol>
<p>
<ul>
<li>tofu
<li>rice
<li>mango
<li>almonds
</ul>
</blockquote>
<hr>
To explain the syntax ... surround a word/phrase with
underlines '_' to italicize it and with asterisks '*' to embolden it.
<p>
Hypertext links are indicated by three percent signs '%' with the
thing to click on first and then the web address.
Links will open in a new window since they're likely external to
the MMC site.
<p>
Blank lines start a new paragraph.
<p>
Lines beginning with '#' create a numbered list that
ends with the next paragraph.
Lines beginning with '-' create a bulleted list.
<p>
Finally, the constructs with __, **, %%%, and ~~ need to be on the <i>same</i> line.
No fair trying to put them on separate lines.
The first _ and * need to appear either after a blank
or at the beginning of the line - in case an underscore or star
is needed elsewhere - like in a web address.
<a name=publication>
<h2>Publication</h2>
Once <span class=emphasize style="font-size: 26pt">all</span> this
input has been
done the rest of the process is <span class=emphasize>very</span> simple. 
In 'reg' from the top menu choose Program-Publish (or if you're on
the registration screen choose Jump-Program-Publish).
<p>
This simple act of publishing does all of these things:
<ul>
<li>Generate a web page from template.tmpl for each
program that is 'webready' and not past.  It links them
all together properly with next and prev links.
Some programs may have their own template file and may
choose to not be linked up with the others.
These web pages are named like this: <span class=path>AND-6-9.html</span>
where the program name is ANDERSON and it occurs on June 9th.
<li>Generate the event and program listings ordered by starting date
and use them
to generate events.html and programs.html from templates by the same name.
<li>Create a file named <span class=path>regtable</span> which
is used for program information by the online reg program 'reg1'.
<li>ftp to www.mountmadonna.org and transfer
<span class=path>regtable</span> and all .html files
to the directory <span class=path>/home/mmc/www/staging</span>
</ul>
<p>
Also in 'reg'
from the top menu choose Program-Other-PublishPics (or if you're on
the registration screen choose Jump-Program-Other-PublishPics).
All .jpg and .gif files in
<span class=path>pics/</span> will be ftp'ed to www.mountmadonna.org in
the directory <span class=path>/home/mmc/www/staging/pics</span>.
Note that this second act of publishing needs to be done
only when you have added (or deleted) pictures in the
<span class=path>/v/reg/web/pics</span> directory.
<p>
At this point the webmaster should verify that all is well
in the staging area
by checking out
<a href="http://www.mountmadonna.org/staging/events.html">events.html</a>
and
<a href="http://www.mountmadonna.org/staging/programs.html">programs.html</a>.
When testing online registration use a credit card
number of 4111 1111 1111 1111 and any expiration date like 0805.
This will do a "TEST MODE" submission to the credit card company.
<p>
Once all is well go to:
<ul>
<a href="http://www.mountmadonna.org/cgi-bin/admin">www.mountmadonna.org/cgi-bin/admin</a>.
</ul>
This is the admin approval page
where you will find a button for moving Staging to Live.
If you encounter a problem you can
restore the previous live pages with another button on the same page.
<p>
Also on that page is a way of managing the unlinked programs.
Instead of giving Open Gate Sangha an address like this:
<ul>
www.mountmadonna.org/live/OPE-7-13.html
</ul>
we can use this more appealing and memorable form:
<ul>
www.mountmadonna.org/ogs
</ul>
On the admin page you can create this.  You can also
purge the expired unlinked programs - ones that have already happened
and for which online registration no longer makes sense.
<a name=brochure>
<h2>Brochure</h2>
After entering the Leader and Program information you
can create an input file for the brochure.  From the top
menu of 'reg' choose Program-Other-Brochure.  It will first
ask you which season the brochure is for and which
page of the brochure will contain the normal fee table.
It then creates a file named 'brochure' in your home directory.
That file will be in a format suitable for importing into Quark.

<a name=transfer>
<h2>Transfer</h2>
There are many files on the Unix machine and at www.mountmadonna.org
that need to be edited and tweaked (but hopefully not endlessly).
Rather than requiring a login to
those machines where you would need to use vi it is easier
to edit them on your local Windows box and then ftp them to
the appropriate spot.  But even this is error prone since
you have to make sure that you put them in the right places.
The Perl/Tk script, 'transfer.pl', is essentially a custom scripted
ftp.   The interface consists of a single button to press.
It turns pink when you press it and when the transfers are
done it turns back to white.  Edit the files in DreamWeaver
or a CSS editor or Notepad and then press "Transfer Files".
Is that easy enough?

<a name=perl>
<h2>Perl, Javascript and Shell Scripts,<br>
Style Sheets and non-program HTML Templates</h2>
This section contains a complete list of scripts used
in this online reg project.
<p>
Here's a table of places where the scripts live.
<p>
<table cellpadding=5 border=1>
<tr><th>Letter</th><th align=left>Machine</th><th align=left>Directory</th></tr>
<tr><td align=center>V</td><td>your own local windows machine</td><td>your choice</td></tr>
<tr><td align=center>W</td><td>the unix machine at mmc</td><td>/v/reg/web</td></tr>
<tr><td align=center>X</td><td>the unix machine hosting www.mountmadonna.org</td><td>cgi-bin/</td></tr>
<tr><td align=center>Y</td><td>the unix machine hosting www.mountmadonna.org</td><td>www/onlinereg/</td></tr>
<tr><td align=center>Z</td><td>the unix machine hosting www.mountmadonna.org</td><td>www/</td></tr>
</table>
<p>
<table border=1 cellpadding=5>
<tr>
<th>&nbsp;</th>
<th align=left>Letter</th>
<th align=left>Filename</th>
<th align=left>Purpose</th>
</tr>

<tr>
<td>1</td><td align=center>V</td><td>
transfer.pl
</td><td>
A Perl/Tk program that reads script.txt and ftps files here and there.
It enables local editing of distant files.
</td></tr>

<tr>
<td>2</td><td align=center>V</td><td>
script.txt
</td><td>
The script of ftp access points and commands for transfer.pl.
</td></tr>

<tr>
<td>3</td><td align=center>W</td><td>
gen
</td><td>
The main program that takes all the input files and generates
the program html pages, the event and program calendars,
regtable and this document, cms_mmc.html.  This document is
actually embedded in the __DATA__ section of gen as a kind
of advanced POD.
</td></tr>

<tr>
<td>4</td><td align=center>W</td><td>
Date/Simple.pm
</td><td>
General date routines.
</td></tr>

<tr>
<td>5</td><td align=center>W</td><td>
Util.pm
</td><td>
3 utility routines.
</td></tr>

<tr>
<td>6</td><td align=center>W</td><td>
Image/Size.pm
</td><td>
Sizing of jpg and gif formats.
</td></tr>

<tr>
<td>7</td><td align=center>W</td><td>
Leader.pm
</td><td>
Leader class to deal with everything leaders.
</td></tr>

<tr>
<td>8</td><td align=center>W</td><td>
Program.pm
</td><td>
Reads the programs.tmp file and deals with everything programs.
</td></tr>

<tr>
<td>9</td><td align=center>W</td><td>
Lookup.pm
</td><td>
Reads the config/lookup.txt file and exports a hash.
</td></tr>

<tr>
<td>10</td><td align=center>W</td><td>
Rental.pm
</td><td>
Reads the rentals.tmp file and deals with everything rentals.
</td></tr>

<tr>
<td>11</td><td align=center>W</td><td>
Housing.pm
</td><td>
Reads the housing.tmp file and deals with everything housing.
</td></tr>

<tr>
<td>12</td><td align=center>W</td><td>
Exception.pm
</td><td>
Reads the config/exceptions.txt file and exports one method named 'except'.
</td></tr>

<tr>
<td>13</td><td align=center>W</td><td>
genpages.sh
</td><td>
Invokes gen and ftps regtable and *.html files to
www.mountmadonna.org/www/staging.
This is invoked from within /v/reg/prg/dumpall.prg when the
Program-Publish command is given.  What that program
first does is dump several tables into temporary text files
in /v/reg/web.
<p>
<table cellpadding=5 border=1>
<tr><th align=left>DBF file</th><th align=left>tmp file</th></tr>
<tr><td>cur/prog (not rental)</td><td>programs.tmp</td></tr>
<tr><td>sys/leader</td><td>leaders.tmp</td></tr>
<tr><td>sys/housing</td><td>housing.tmp</td></tr>
<tr><td>cur/prog (rental)</td><td>rentals.tmp</td></tr>
</table>
</td></tr>

<tr>
<td>14</td><td align=center>W</td><td>
.netrc
</td><td>
A configuration file that lives in $HOME with permissions
of 600.  It enables non-interactive use of ftp.
</td></tr>

<tr>
<td>15</td><td align=center>W</td><td>
saveall.sh
</td><td>
A shell file to gather all important files in this project,
tar them together, compress the tarfile and
and ftp it to www.mountmadonna.org/www/onlinereg.
This script is invoked from /v/reg/prg/pgm.prg when the
Program-Other-Save command is given.
The files are gathered from whereever they normally live whether
that be locally on the Unix machine or on www.mountmadonna.org.
</td></tr>

<tr>
<td>16</td><td align=center>W</td><td>
putpics.sh
</td><td>
A shell file to ftp /v/reg/web/pics/* to www.mountmadonna.org/www/staging/pics.
This is invoked from /v/reg/prg/pgm.prg when the
Program-Other-PublishPics command is given.
</td></tr>

<tr>
<td>17</td><td align=center>W</td><td>
getonreg.sh
</td><td>
Shell script invoked by reg command Other-Online
to retrieve the transactions/ files created by the relay program.
It transfers them to the /v/reg/online directory.
See on_line.prg in /v/reg/prg.
That program takes care of doing the registration in reg.
</td></tr>

<tr>
<td>18</td><td align=center>W</td><td>
cmpall
</td><td>
Perl script to compare development files to production files.
</td></tr>

<tr>
<td>19</td><td align=center>X</td><td>
reg1
</td><td>
CGI script invoked by pressing the "Register Online" button
on program web pages.  Parameters are test, prognum and dir.
'test' is 1 for staging and 0 for live.
'prognum' is the sequential number of the program within
the regtable file.
'dir' says what subdirectory of /home/mmc/www will have
the regtable it needs.
<p>
It presents a form for the registrant to fill in asking
for demographics, housing choice, etc.
</td></tr>

<tr>
<td>20</td><td align=center>X</td><td>
reg2
</td><td>
CGI script to process the form generated by reg1.
It validates the fields, sets cookies, and then presents the confirmation
page to the user.  They can then choose a payment method.
</td></tr>

<tr>
<td>21</td><td align=center>X</td><td>
reg3
</td><td>
CGI script to generate the "Pay by Mail or Fax" page.
</td></tr>

<tr>
<td>22</td><td align=center>X</td><td>
reg1.html
</td><td>
Template filled in by reg1.
</td></tr>

<tr>
<td>23</td><td align=center>X</td><td>
reg2.html
</td><td>
Template filled in by reg2.
</td></tr>

<tr>
<td>24</td><td align=center>X</td><td>
reg3.html
</td><td>
Template filled in by reg3.
</td></tr>

<tr>
<td>25</td><td align=center>X</td><td>
admin
</td><td>
A Perl script to administer the staging, live and
unlinked program pages.
</td></tr>

<tr>
<td>26</td><td align=center>X</td><td>
relay
</td><td>
Perl script invoked by the authorize.net process.
It creates a file in the<br>cgi-bin/transactions directory
describing the transaction.  These files are retrieved
(via the ftp inside getonreg) when invoking the Other-Online command in reg.
</td></tr>

<tr>
<td>27</td><td align=center>X</td><td>
SimLib.pm
</td><td>
Perl module provided by authorize.net.
</td></tr>

<tr>
<td>28</td><td align=center>X</td><td>
SimHMAC.pm
</td><td>
Perl module provided by authorize.net.
</td></tr>

<tr>
<td>29</td><td align=center>Y</td><td>
formval.css
</td><td>
Style sheet used in reg1.html for form validation items.
</td></tr>

<tr>
<td>30</td><td align=center>Y</td><td>
formval.js
</td><td>
Javascript for form validations borrowed from somewhere on the web.
Written by Stephen Poley.
</td></tr>

<tr>
<td>31</td><td align=center>Z</td><td>
mmc.css
</td><td>
Style sheet used by the entire www.mountmadonna.org site.
</td></tr>

</table>

</td></tr></table></body>
</html>
}
