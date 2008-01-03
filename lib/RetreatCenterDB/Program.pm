use strict;
use warnings;
package RetreatCenterDB::Program;
use base qw/DBIx::Class/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('program');
# Set columns in table
__PACKAGE__->add_columns(qw/
    id
    name
    title
    subtitle
    glnum
    housecost_id
    retreat
    sdate
    edate
    tuition
    confnote
    url
    webdesc
    brdesc
    webready
    image
    kayakalpa
    canpol_id
    extradays
    full_tuition
    deposit
    collect_total
    linked
    ptemplate
    sbath
    quad
    economy
    footnotes
    school
    level
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

# relationships
__PACKAGE__->belongs_to(canpol => 'RetreatCenterDB::CanPol', 'canpol_id');
__PACKAGE__->belongs_to(housecost => 'RetreatCenterDB::HouseCost',
                        'housecost_id');

__PACKAGE__->has_many(affil_program => 'RetreatCenterDB::AffilProgram',
                      'p_id');
__PACKAGE__->many_to_many(affils => 'affil_program', 'affil',
                          { order_by => 'descrip' },
                         );

__PACKAGE__->has_many(leader_program => 'RetreatCenterDB::LeaderProgram',
                      'p_id');
__PACKAGE__->many_to_many(leaders => 'leader_program', 'leader');
    # sort order???

#
# we really can't call $self->{field}
# but must call $self->field()
# or just $self->field;
#
# something about when it actually does populate the object...???
#

use Date::Simple qw/date/;
use Util qw/slurp expand/;
use Lookup;

my $default_template = slurp("template");

sub sdate_obj {
    my ($self) = @_;

    return date($self->sdate) || "";
}
sub edate_obj {
    my ($self) = @_;

    return date($self->edate) || "";
}
sub fname {
    my ($self) = @_;

	# was it computed before?
	if (exists $self->{fname}) {
		print "already $self->{fname}\n";
		return $self->{fname}
	}
    my $sd = $self->sdate_obj;
    my $name =
           "gen_files/" .
		   substr($self->name,  0, 3) .
           "-" .
           $sd->month .
           "-" .
           $sd->day;
	if (-f "$name.html") {
		# one extra should be enough, yes?
		$name .= "a";
	}
	$name .= ".html";
    if (! $self->linked) {   # ul = unlinked
        $name = "ul_$name";
    }
	$self->{fname} = $name;
	system("touch $name");		# tricky!
			# we need the above or else the file will not
			# exist when we do the -f check above.
            # ??? really?   isn't it created immediately?
	$name;
}
sub template_src {
	my ($self) = @_;
	return ($self->ptemplate)? 
		slurp($self->ptemplate):
		$default_template;
}

sub title1 {
    my ($self) = @_;
    return ($self->leaders_str && $self->leaders_str !~ m{staff}i)?
                $self->leaders_str:
                $self->title;
}
sub title2 {
    my ($self) = @_;
    if ($self->leaders_str && $self->leaders_str !~ m{staff}i) {
        if ($self->subtitle) {
            $self->title . " - " . $self->subtitle;
        } else {
            $self->title;
        }
    } else {
        $self->subtitle;
    }
}
sub barnacles {
    my ($self) = @_;
    my $b = $self->footnotes;
    $b =~ s/\+/&dagger;/g;
    $b =~ s/%/&sect;/g;
	$b = "<span class='barnacles'><sup>$b</sup></span>" if $b;
    $b;
}
sub title1_barnacles {
    my ($self) = @_;
	return (($self->leaders_str or $self->subtitle)?
			   "":
			   $self->barnacles);
}
sub title2_barnacles {
    my ($self) = @_;
	return (($self->leaders_str or $self->subtitle)?
		       $self->barnacles:
		       "");
}
sub leaders_str {
    my ($self) = @_;
    if ($self->{leaders_str}) {
        return $self->{leaders_str};
    }
    my $s = "";
    my @leaders = map {
                      $_->person->first . " " . $_->person->last
                  }
                  sort {
                      $a->person->last  cmp $b->person->last or
                      $a->person->first cmp $b->person->first
                  }
                  $self->leaders;
    my $last = pop @leaders;
    $s .= join ", ", @leaders;
    $s .= " and " if $s;
    $s .= $last;
    $self->{leaders_str} = $s;
}
sub prog_dates_style {
    my ($self) = @_;
	return (($self->leaders_str or $self->subtitle)?
			   "":
			   "style='vertical-align: bottom'");
}
sub webdesc_plus {
    my ($self) = @_;
    my $s = expand($self->webdesc);
    my $barnacles = $self->footnotes;
	if ($barnacles) {
		$s .= "<ul>\n";
		if ($barnacles =~ /\*\*/) {
			$s .= "<li>$lookup{'**'}\n";
		} elsif ($barnacles =~ /\*/) {
			$s .= "<li>$lookup{'*'}\n";
		}
		$s .= "<li>$lookup{'+'}\n" if $barnacles =~ /\+/;
		$s .= "<li>$lookup{'%'}\n" if $barnacles =~ /%/;
		$s .= "</ul>\n";
	}
    $s;
}
sub weburl {
    my ($self) = @_;
    my $url = $self->url;
    return "" unless $url;
    return "<p>$lookup{weburl} <a href='http://$url' target='_blank'>$url</a>.";
}
sub month_calendar {
    my ($self) = @_;
    my $m = $self->sdate_obj->month;
	my $cal = slurp("cal$m.tmp");
    $cal;
}

#
# generate HTML (yes :() for a fee table)
#
sub fee_table {
    my ($self) = @_;

    my $sdate = $self->sdate_obj;
    my $month = $sdate->month;
    my $edate = $self->edate_obj;
    my $extdays  = $self->{extdays};
    my $ndays = ($edate-$sdate) || 1;		# personal retreats exception
    my $fulldays = $ndays + $extdays;
    my $cols  = ($extdays)? 3: 2;
	my $pr    = $self->name =~ m{personal retreat}i;
	my $tent  = $self->name =~ m{tnt}i;

    my $fee_table = <<EOH;
<p>
<table>
EOH
	$fee_table .= <<EOH unless $self->name eq "PERSONAL RETREATS";
<tr><th colspan=$cols>$lookup{heading}</th></tr>
<tr><td colspan=$cols>&nbsp;</td></tr>
EOH
    $fee_table .= "<tr><th align=left valign=bottom>$lookup{typehdr}</th>";
    if ($extdays) {
        $fee_table .= "<th align=right width=70>$ndays Days</th>".
                      "<th align=right width=70>$fulldays Days</th></tr>\n";
    } else {
        $fee_table .= "<th align=right>$lookup{costhdr}</th></tr>\n";
    }
    for my $t (Housing->types) {
        next if $t =~ m{unknown};
        next if $t =~ m{economy}     && ! $self->economy;
        next if $t =~ m{quad}        && ! $self->quad;
		next if $t =~ m{single bath} && ! $self->sbath;

        next if $t =~ m{center tent} && ! (5 <= $month and $month <= 10)
									 && ! ($pr || $tent);
										# ok for PR's - we don't
										# know what month...
		next if $pr and $t =~ m{triple|dorm};
		my $cost = $self->_fees(0, $t);
		next unless $cost;		# this type of housing is not offered at all.
        $fee_table .= "<tr><td>$lookup{$t}</td>";
        $fee_table .= "<td align=right>$cost</td>\n";
        if ($extdays) {
            $fee_table .= "<td align=right>" .
             $self->_fees(1, $t) .
             "</td>\n";
        }
        $fee_table .= "</tr>\n";
    }
    $fee_table .= "</table>\n";
    return $fee_table;
}

#
# fees for a given program, a given type and full/basic
#
sub _fees {
    my ($self, $full, $type) = @_;

    $type =~ s{^\s*|\s*$}{}g;    # trim front and back
    die "illegal housing type: $type" unless Housing->valid($type);
    my $tuition = $self->{($full)? "fulltuit": "tuition"};
    my $housing = $self->housecost;
    my $ndays = ($self->edate - $self->sdate) || 1;
										# personal retreat exception
    $ndays += $self->extdays if $full;
    #
    # the 'housing' field is either 0 or 1-5 or 6-8
    # 0, 6-8 are per day costs
    # 1-5 are total costs
    #
    # there is a housing discount of 10% for programs of 7 days or longer
    # and a further housing discount of 10% MORE for programs 30 days or longer.
	#
	# what if there are extra days and 1 <= $housing <= 5?
	# this is as yet unanswered.
    #
    my $hcost = Housing->cost($housing, $type);
	unless (1 <= $housing and $housing <= 5) {
		$hcost = $ndays*$hcost;
		$hcost -= 0.10*$hcost  if $ndays >= 7;
		$hcost -= 0.10*$hcost  if $ndays >= 30;
		$hcost = int($hcost);
	}
	return 0 unless $hcost;		# don't offer this housing type if cost is zero
    return $tuition + $hcost;
}

1;
