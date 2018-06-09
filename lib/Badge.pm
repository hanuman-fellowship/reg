use strict;
use warnings;
package Badge;

use Util qw/
    empty
    model
    get_grid_file
    normalize
/;
use Global qw/
    %house_name_of
/;

my $html;
my $tt;
sub initialize {
    my ($class, $c) = @_;
    my @badge_strs = model($c, 'String')->search({
                         the_key => { 'like' => 'badge_%' },
                     });
    my %hash;
    for my $bs (@badge_strs) {
        my $bk = $bs->the_key();
        $bk =~ s{\A badge_}{}xms;
        $hash{$bk} = $bs->value();
    }
    $html = undef;
    $tt = Template->new({
              INCLUDE_PATH => 'root/src',
              INTERPOLATE => 1,
          }) or die Template->error();
    $tt->process(
        'registration/badge_top.tt2',
        \%hash,
        \$html,
    );
}

sub add_group {
    my ($class, $program, $code, $data_aref) = @_;
    for my $d_href (@$data_aref) {
        if (length($d_href->{name}) > 20) {
            $d_href->{name_class} = 'long_name';
        }
    }
    my $stash = {
        program => $program,
        code    => $code,
    };
    for (my $i = 0; $i <= $#$data_aref; $i += 6) {
        $stash->{data}  = [ @{$data_aref}[$i .. $i+5] ];
        $tt->process(
            'registration/badge.tt2',
            $stash,
            \$html,
        ) or die Template->error();
    }
}

sub finalize {
    $html =~ s{<div style='page-break-after:always'></div>\n\z}{};
    $html .= <<'EOH';
</body> 
<script>
window.print();
</script>
</html>
EOH
    return $html;
}

# returns $mess, $title, $code
sub get_title_code {
    my ($class, $event) = @_;
    my $title = $event->badge_title();
    if (empty($title)) {
        $title = $event->title();
    }
    $title =~ s{\A (Special \s+ Guest) .*}{$1}xms;
    $title =~ s{\A (Personal \s+ Retreat) .*}{$1}xms;
    my $code = $event->summary->gate_code();
    my $name = $event->name;
    my $mess;
    if (empty($title)) {
       $mess = "<br>$name - Need a Badge Title"; 
    }
    if (length($title) > 30) {
        $mess .= "<br>$name - Badge Title is too long to properly fit.";
    }
    if (empty($code)) {
        $mess .= "<br>$name - Missing Gate Code - add it in the Summary";
    }
    return ($mess, $title, $code);
}

sub get_badge_data_from_program {
    my ($class, $c, $program) = @_;

    my ($mess, $title, $code) = $class->get_title_code($program);
    if ($mess) {
        # cannot proceed
        return $mess;
    }
    my @regs = model($c, 'Registration')->search(
        {
            program_id     => $program->id,
            cancelled      => '',
        },
        {
            join     => [qw/ person /],
            order_by => [qw/ person.first person.last /],
            prefetch => [qw/ person /],   
        }
    );
    my @data;
    for my $r (@regs) {
        push @data, {
            name  => $r->person->name(),
            dates => $r->dates(),
            room  => $r->house_name(),
        };
    }
    return ($mess, $title, $code, \@data);
}

sub get_badge_data_from_rental {
    my ($class, $c, $rental) = @_;
        # $c is unused here - but we include it
        # to keep symmetry with the above sub for programs...
    my ($mess, $title, $code) = $class->get_title_code($rental);
    if ($mess) {
        # cannot proceed
        return $mess;
    }
    my $d = $rental->sdate_obj();
    my $ed = $rental->edate_obj();

    # get the most recent edit from the global web
    #
    my $fgrid = get_grid_file($rental->grid_code());

    my $in;
    if (! open $in, "<", $fgrid) {
        my $name = $rental->name();
        $mess = "$name - Cannot get the current local grid!";
        # cannot proceed
        return $mess;
    }
    my @data;
    LINE:
    while (my $line = <$in>) {
        chomp $line;
        my ($id, $bed, $name, @nights) = split m{\|}, $line;
        my $cost = pop @nights;
        if (!$cost) {
            # no one is in that room
            next LINE;
        }
        my $room = ($id == 1001)? 'Own Van'
                  :($id == 1002)? 'Commuting'
                  :               $house_name_of{$id}
                  ;

        # trim any extra info after the delimiter ~~
        $name =~ s{ ~~ .* }{}xms;

        # for 'child', '&', and 'and', see below
        
        # what nights?
        my $this_d = $d;
        my $this_ed = $ed;
        while ($nights[0] == 0) {
            shift @nights;
            ++$this_d;
        }
        while ($nights[-1] == 0) {
            pop @nights;
            --$this_ed;
        }
        my $dates = $this_d->format("%b %e")
                  . ' - '
                  . $this_ed->format("%b %e")
                  ;
        my @names = split m{ \s*
                             (?: [&] | \band\b | [/])    # and /
                             \s*
                           }xmsi, $name;
        for my $n (@names) {
            $n =~ s{ \b child \s* \z}{}xmsi;
            push @data, {
                name  => normalize($n),
                dates => $dates,
                room  => $room,
            };
        }
    }
    close $in;
    @data = sort {
                lc $a->{name} cmp lc $b->{name}
            }
            @data;
    return ($mess, $title, $code, \@data);
}

1;
