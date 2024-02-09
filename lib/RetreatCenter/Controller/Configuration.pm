use strict;
use warnings;
package RetreatCenter::Controller::Configuration;
use base 'Catalyst::Controller';

use lib '../../';
use Util qw/
    stash
    model
    time_travel_class
    tt_today
    slurp
    JON
/;
use Date::Simple qw/
    date
    today
/;
use Time::Simple qw/
    get_time
/;
use File::Copy qw/
    copy
/;

use Global;
use File::stat;
my $words = "/var/Reg/words";

sub index : Local {
    my ($self, $c) = @_;

    stash($c,
        time_travel_class($c),
        pg_title => "Configuration",
        files_uploaded => $c->flash->{files_uploaded}||'',
        template => "configuration/index.tt2",
    );
}

sub mark_inactive : Local {
    my ($self, $c) = @_;

    my ($date_last) = $c->request->params->{date_last};
    my $dt = date($date_last);
    if (! $dt) {
        stash($c,
            mess     => "Invalid date: $date_last",
            template => 'listing/error.tt2',
        );
        return;
    }
    my $dt8 = $dt->as_d8();
    my $n = model($c, 'Person')->search({
        inactive => '',
        date_updat => { "<=", $dt8 },
    })->count();
    stash($c,
        date_last => $dt,
        count     => $n,
        template  => 'listing/inactive.tt2',
    );
}

sub mark_inactive_do : Local {
    my ($self, $c, $date_last) = @_;
}

sub counts : Local {
    my ($self, $c) = @_;

    my @classes = map {
                      +{
                          name  => $_,
                          count => scalar(model($c, $_)->search),
                                # scalar context gives the count
                      }
                  }
                  sort
                  @{RetreatCenterDB->classes()};
    stash($c,
        classes  => \@classes,
        template => 'configuration/counts.tt2',
    );
}

sub _get_words {
    my ($file, $aref) = @_;
    open my $in, '<', $file;
    @$aref = <$in>;
    close $in;
    chomp @$aref;
}

sub spellings : Local {
    my ($self, $c, $reg_id) = @_;
    my (@okay, @maybe);
    _get_words("$words/okaywords.txt",  \@okay);
    _get_words("$words/maybewords.txt", \@maybe);
    stash($c,
        reg_id   => $reg_id,
        okay     => \@okay,
        maybe    => \@maybe,
        template => 'configuration/spellings.tt2',
    );
}
sub spellings_do : Local {
    my ($self, $c, $reg_id) = @_;

    my %P = %{ $c->request->params() };
    my (@okay, %not_okay);
    _get_words("$words/okaywords.txt", \@okay);
    for my $k (sort keys %P) {
        my ($type, $w) = $k =~ m{ \A (maybe|okay)_(\S+) \z }xms;
        if ($type eq 'maybe') {
            push @okay, $w;
        }
        else {
            $not_okay{$w} = 1;
        }
    }
    open my $out, '>', "$words/okaywords.txt";
    # need to sort case insensitively
    for my $w (
        map { $_->[0] } 
        sort { $a->[1] cmp $b->[1] }
        map { [ $_, lc $_ ] }
        @okay
    ) {
        print {$out} "$w\n" unless exists $not_okay{$w};
    }
    close $out;
    open my $empty, '>', "$words/maybewords.txt";
    close $empty;
    $c->response->redirect("/registration/view/$reg_id");
}

#
# for updating these few special 'fixed' documents:
#
# Info Sheet.pdf
# Kaya Kalpa Brochure.pdf
# Main Area Map.pdf
# MMC Food.pdf
# MMC Guest Packet.pdf
# Program Guest Confirmation Letter.pdf
# Program Registration Guidelines.pdf
#
sub documents : Local {
    my ($self, $c) = @_;
    stash($c,
        pg_title => "Documents for Reg",
        template => 'configuration/documents.tt2',
    );
}

# 'our' so we can reference it from elsewhere...
our %file_named = (
    a_info        => 'Info Sheet.pdf',
    b_kaya        => 'Kaya Kalpa Brochure.pdf',
    c_main_map    => 'Main Area Map.pdf',
    d_food        => 'MMC Food.pdf',
    e_packet      => 'MMC Guest Packet.pdf',
    f_rental_conf => 'Program Guest Confirmation Letter.pdf',
    g_rental_reg  => 'Program Registration Guidelines.pdf',
    h_me_guest    => 'Guest-Packet_MountainExperience.pdf',
);

sub documents_do : Local {
    my ($self, $c) = @_;
    my @mess;
    my %uploads;
    for my $k (sort keys %file_named) {
        my $fname = $file_named{$k};
        if (my $upload = $c->request->upload($k)) {
            if ($upload->filename() ne $fname) {
                push @mess, "The file '" . $upload->filename
                          . "' should be named '$fname'."
                          ;
            }
            else {
                $uploads{$fname} = $upload;
            }
        }
    }
    if (@mess) {
        stash($c,
            mess     => join('<br>', @mess),
            template => 'gen_error.tt2',
        );
        return;
    }
    if (%uploads) {
        my $dir = '/var/Reg/documents';
        my $now = get_time();
        my $now_t24 = $now->t24;
        my $today = tt_today($c);
        my $today_d8 = $today->as_d8();
        for my $fname (sort keys %uploads) {
            copy("$dir/$fname", "$dir/$fname-$today_d8-$now_t24");
            $uploads{$fname}->copy_to("$dir/$fname");
            model($c, 'Activity')->create({
                message => "Uploaded document '$fname'",
                ctime   => $now_t24,
                cdate   => $today_d8,
            });
        }
        $c->flash->{files_uploaded} = join('<br>', sort keys %uploads);
    }
    $c->response->redirect('/configuration/index');
}

my $dr_file = "$words/date_ranges.txt";
sub date_ranges : Local {
    my ($self, $c) = @_;

    my $date_ranges = "";
    if (-f $dr_file) {
        $date_ranges = slurp($dr_file);
    }
    stash($c,
        date_ranges => $date_ranges,
        template => 'configuration/date_ranges.tt2',
    );
}

sub date_ranges_do : Local {
    my ($self, $c) = @_;

    my @lines = grep { /\S/ }   # skip blank lines
                split "\cM\n", $c->request->params->{date_ranges};
    my $mess = "";
    LINE:
    for my $line (@lines) {
        my ($type, $range, $max) = split ' ', $line;
        if (! ($type && $range && $max)) {
            $mess .= "Invalid format: $line<br>";
            next LINE;
        }
        if ($range !~ m{\d{8}[-]\d{8}}xms) {
            $mess .= "Illegal date range: $range<br>";
            next LINE;
        }
        my ($start, $end) = split '-', $range;
        if ($type !~ m{\A ME|PR \z}xms) {
            $mess .= "Illegal type: $type<br>";
        }
        my $st = date($start);
        if (! $st) {
            $mess .= "Illegal date: $start<br>";
        }
        my $en = date($end);
        if (! $en) {
            $mess .= "Illegal date: $end<br>";
        }
        if ($st && $en && $st > $en) {
            $mess .= "Start date $start is after the End date $end<br>";
        }
        if ($max !~ m{\A \d+ \z}xms) {
            $mess .= "Max value is not numeric: $max";
        }
    }
    if ($mess) {
        stash($c,
            mess     => $mess,
            template => 'listing/error.tt2',
        );
        return;
    }
    open my $out, '>', $dr_file;
    print {$out} map { "$_\n" } @lines;
    close $out;
    $c->response->redirect('/configuration/index');
}

my $dir = "/var/Reg/output";
#my $fname = "mmc_rg_export.zip";
my $fname = "mmc_rg_export.tar";

my $Reg_id_RG_id_mapping = <<'EOM';
1   63  CC 101
2   93  CC 102 Ensuite
3   64  CC 103
4  145  CC 104 Ensuite
12   94  CC 105 ADA
13   89  CC 107
14   95  CC 108 ADA Ensuite
15   65  CC 109
16   90  CC 110 Triple
17   66  CC 111
18   96  CC 112 Ensuite
19   67  CC 113
20   97  CC 114 Ensuite
21   91  CC 115
22   98  CC 116 Ensuite
23   92  CC 117
24   99  CC 118 Ensuite
5   68  CC 201
27   69  CC 202 Triple
6   70  CC 203
28   71  CC 204 Triple
31  100  CC 205
29  101  CC 206 Triple
32  102  CC 207
30  103  CC 208 Triple
25  104  CC 209
26  105  CC 210 Triple
33  106  CC 211
34  110  CC 212 Ensuite
35  107  CC 213
36  111  CC 214 Ensuite
37  108  CC 215
38  112  CC 216 Ensuite
39  109  CC 217
40  113  CC 218 Ensuite
117  152  Oaks Cabin 1
118  153  Oaks Cabin 2
119  154  Oaks Cabin 3
120  155  Oaks Cabin 4
121  156  Oaks Cabin 5
122  157  Oaks Cabin 6
123  158  Oaks Cabin 7
124  159  Oaks Cabin 8
125  160  Oaks Cabin 9
314  195  Ram 1 Whole Cottage
41  114  Ram 1A
42  115  Ram 1B
43  116  Ram 2A
44  117  Ram 2B
45  118  Ram 2C
315  119  Ram 3A
316  120  Ram 3B
7  121  SH 1 Triple
8  122  SH 2 Triple
9  123  SH 3 Triple
10  124  SH 4 Triple
11  125  SH 5 Double
183  196  SH Main
100  129  Tent Madrone 1
105  130  Tent Madrone 2
106  131  Tent Madrone 3
101  132  Tent Madrone 4
107   75  Tent Madrone 5
102   76  Tent Madrone 6
103  149  Tent Madrone 7
108  150  Tent Madrone 8
104  151  Tent Madrone 9
111  148  Tent Madrone A
273  133  Tent Oaks 11
47  134  Tent Oaks 12
48  135  Tent Oaks 13
49  136  Tent Oaks 14
50   88  Tent Oaks 15
78   77  Tent Oaks 16
79   78  Tent Oaks 17
80   81  Tent Oaks 18
51   82  Tent Oaks 19
52   72  Tent Oaks 20
53   73  Tent Oaks 21
54   74  Tent Oaks 22
81   79  Tent Oaks 23
55   80  Tent Oaks 24
56  163  Tent Oaks 25
82  166  Tent Oaks 26
57  167  Tent Oaks 27
83  168  Tent Oaks 28
58  169  Tent Oaks 29
84  170  Tent Oaks 30
85  171  Tent Oaks 31
86  172  Tent Oaks 33
87  173  Tent Oaks 34
61  174  Tent Oaks 36
62  175  Tent Oaks 37
88  176  Tent Oaks 38
63  177  Tent Oaks 39
89  178  Tent Oaks 40
64  179  Tent Oaks 41
65  180  Tent Oaks 42
90  181  Tent Oaks 43
91  182  Tent Oaks 44
66  183  Tent Oaks 45
67  184  Tent Oaks 46
68  185  Tent Oaks 47
92  186  Tent Oaks 48
69  188  Tent Oaks 49
70  187  Tent Oaks 50
71  189  Tent Oaks 51
93  190  Tent Oaks 52
94  191  Tent Oaks 53
72  192  Tent Oaks 54
95  193  Tent Oaks 55
73  194  Tent Oaks 56
99  165  Tent Oaks 64
EOM
my @prog_headers = qw/
program_id_original
title
*description
*date_type
date_start
date_end
list_until_date
*datetime_details
*organization_id
*organization_id_original
*featured-image
*gallery
*location
*location_address
contact_email
contact_phone
contact_name
*price_structure
*first_price
*lodging_ids
*price_note
*capacity_max
*categories
*email_message
/;
my @reg_headers = qw/
registration_id_original
first_name
last_name
email
*program_id
program_id_original
*status
time_submitted
arrive_date
leave_date
*person_id_original
room_id
*lodging_id
*parent_registration_id_original
address
address2
city
state
zip
country
*dates-flexible
*rs-inquiry-organization
*date-notes
*organization-type
*rs-inquiry-number-of-people
*rs-inquiry-event-description
*other-event-type
*org-web-page
*rs-inquiry-email
*rs-inquiry-firstname
*guest_type
*flag-person
*black_listed
*flag-notes
*person-notes
*person-skills
*flagged
*reg-flag-notes
*reg-notes
*housekeeping-notes
*site-referrer
*firstname
*lastname
*rs-inquiry-lastname
***mobile-phone
*rs-inquiry-rented-before
phone
*mobile-phone-2
*address-line-1-2
*address-line-2-2
*city-or-region
*state-or-province-2
*zip-or-postal-code
*newsletter
gender
*diet
*diet-notes
*diet-restrictions
*birth-date
*mmc-vegetarian
*participant-registration
*beds-required
*roommate
*emergency-contact
*ride-sharing
*marketing
*been-before
*discount-code
*terms
comments
*bedroom-accommodations
*anything-else
*address-line-1
*address-line-2
*state-or-province
*zip-or-post-code
*country-2
*guaranteed-minimum
*lodging-notes
*meeting-room-notes
*food-and-beverage-notes
*av-services-notes
*payment-terms
*restroom-signage
*ada-requirements
*types-of-meeting-rooms-requested
*preferred-seating-style
*breakout-spaces
*audiovisual-equipment
*other-av-materials
*additional-services
*other-services
/;
my @trans_headers = qw/
object_type
registration_id_original
trans_date
description
category
charge_amount
credit_amount
status
merch_trans_id
fund_method
is_test
notes
/;

sub _quote {
    my ($s) = @_;
    return $s if $s !~ /,/;
    $s =~ s{"}{'}xmsg;
    return qq!"$s"!;
}

sub _gender {
    my ($sex) = @_;
    return ($sex eq 'M' or $sex eq 'male'  )? 'Man'
          :($sex eq 'F' or $sex eq 'female')? 'Woman'
          :($sex eq 'T'                    )? 'Transgender'
          :($sex eq 'R'                    )? 'Prefer not to respond'
          :                                   'Non-binary/Non-conforming'
          ;
}

# ?? all correct slugs?
sub _fund_method {
    my ($type) = @_;
    return $type eq 'C'? 'check'
          :$type eq 'D'? 'credit-card'
          :$type eq 'S'? 'cash'
          :$type eq 'O'? 'online'
          :              'credit-card'
          ;
}

sub _gen_csv {
    my ($c) = @_;
    my %RG_id_for;
    for my $line (split '\n', $Reg_id_RG_id_mapping) {
        my ($Reg_id, $RG_id) = $line =~ m{\A \s* (\d+) \s+ (\d+)}xms;
        $RG_id_for{$Reg_id} = $RG_id;
    }
    open my $prog,  '>', "$dir/programs.csv";
    open my $reg ,  '>', "$dir/registrations.csv";
    open my $trans, '>', "$dir/transactions.csv";
    print {$prog}  join(',', grep { ! /\A[*]/ } @prog_headers),  "\n";
    print {$reg}   join(',', grep { ! /\A[*]/ } @reg_headers),   "\n";
    print {$trans} join(',', grep { ! /\A[*]/ } @trans_headers), "\n";
    my $start = today()->as_d8();
    for my $p (
        model($c, 'Program')->search(
            { edate => { '>=' => $start } },
            { order_by => 'sdate' }
        )
    ) {
        my ($email, $phone, $name);
        my @leaders = $p->leaders;
        if (@leaders) {
            my $lead = $leaders[0];
            my $per = $lead->person;
            $name = $per->name;
            $email = $lead->public_email || $per->email;
            $phone = $per->tel_cell
                     || $per->tel_work
                     || $per->tel_home;;
        }

        # PROGRAM
        print {$prog} join(',',
         $p->id,
         _quote($p->title),
         $p->sdate_obj->format("%F"),
         $p->edate_obj->format("%F"),
         $p->sdate_obj->format("%F"),
         $email,
         $phone,
         $name
        ), "\n";

        REG:
        for my $r ($p->registrations) {
            my $per = $r->person;
            my $time_submitted = '';
            if ($r->date_postmark) {
                $time_submitted = $r->date_postmark_obj->format("%F");
                if ($r->time_postmark) {
                    $time_submitted = ' '
                        .  $r->time_postmark_obj->format('12'),
                }
            }
            my $room_id = 0;
            my $htype = $r->htype;
            if ($r->house_id) {
                $room_id = $RG_id_for{$r->house_id()};
            }
            elsif ($htype eq 'commuting') {
                $room_id = 83;      # RG room 'Commuter 1 - 25p'
                                    #                       50p   ? 85
                                    #                       100p  ? 84
            }
            elsif ($htype eq 'own van') {
                $room_id = 128;     # Lot CC
                                    # Lot Redwood   ? 127
                                    # Lot SH        ? 147
                                    # Lot Log House ? 146
            }
            elsif ($htype eq 'not needed') {
                $room_id = 0;       # ??
            }
            my $comment = $r->comment;
            $comment =~ s{[<][^<]*[>]}{}msg;    # strip tags

            # REGISTRATION
            print {$reg} join(',',
                $r->id,
                $per->first,
                $per->last,
                $per->email,
                $p->id,
                $time_submitted,
                $r->date_start_obj->format("%D"),
                $r->date_end_obj->format("%D"),
                $room_id,
                _quote($per->addr1),
                _quote($per->addr2),
                $per->city,
                $per->st_prov,
                $per->zip_post,
                $per->country,
                $per->tel_cell || $per->tel_home || $per->tel_work,
                _gender($per->sex),
                _quote($comment),
            ), "\n";

            # TRANSACTIONS
                # ?? charges and payments both?
                # or just payments (= credit)
            for my $pay ($r->payments) {
                print {$trans} join(',',
                    'registration', # ??
                    $r->id,
                    $pay->the_date_obj->format("%F"),
                    $pay->what,
                    'payment',      # ??
                    ,               # charge
                    $pay->amount,   # credit
                    'complete',
                    ,               # trans id - do not have
                    _fund_method($pay->type),       # D/C/S/O
                    0, # is test
                    # notes
                ), "\n";
            }
        }
    }

    RENTAL:
    for my $r (
        model($c, 'Rental')->search(
            { edate => { '>=' => $start } },
            { order_by => 'sdate' }
        )
    ) {
        if ($r->program_id) {
            next RENTAL;
        }
        my $contact = $r->coordinator();
        my $name = $contact->name;
        my $email = $contact->email; 
        my $phone = $contact->tel_cell
                    || $contact->tel_home
                    || $contact->tel_work;
        
        # PROGRAM (aka RENTAL)
        print {$prog} join(',',
         $r->id,        # ??? dup with Program? it's okay
         $r->title,
         $r->sdate_obj->format("%F"),
         $r->edate_obj->format("%F"),
         $r->sdate_obj->format("%F"),
         $email,
         $phone,
         $name
        ), "\n";

        # RENTAL DEPOSIT PAYMENTS
        for my $pay ($r->payments()) {
            print {$trans} join(',',
                'rental-payment',   # object-type??
                $r->id,             # rental id
                $pay->the_date_obj->format("%F"),
                ,                   # no description
                'payment',      # ??
                ,               # charge
                $pay->amount,   # credit
                'complete',
                $pay->transaction_id,
                _fund_method($pay->type),       # D/C/S/O
                0, # is test
                # notes
            ), "\n";
        }

        for my $g (model($c, 'Grid')->search({ rental_id => $r->id })) {
            my $room_id = $g->house_id;
            if ($room_id == 1001) {
                $room_id = 128;     # see above
            }
            elsif ($room_id == 1002) {
                $room_id = 83;      # see above
            }
            else {
                $room_id = $RG_id_for{$room_id};
            }
            my @names = split ' ', $g->name;
            my $first = shift @names;
            my $last = "@names";
            my ($email) = $g->notes =~ m{(\S+[@]\S+)}xms;
            # a concocted 'registration'
            my @days = split ' ', $g->occupancy;
                # use @days below
            my ($arr, $dep);
            for my $i (0 .. $#days) {
                if ($days[$i] eq '1') {
                    if (! defined $arr) {
                        $arr = $i;
                    }
                    $dep = $i;
                }
            }
            my $start = ($r->sdate_obj + $arr)->format("%F");
            my $end   = ($r->sdate_obj + $dep + 1)->format("%F");

            # REGISTRATION (aka grid entry)
            print {$reg} join(',',
                $g->rental_id . $g->house_id . $g->bed_num,
                    # a concocted id for transactions
                $first,
                $last,
                $email,
                $r->id,     # the rental id
                '',   # time_submitted,
                $start,
                $end,
                $room_id,
                '', # addr1,
                '', # addr2,
                '', # city,
                '', # st_prov,
                '', # zip_post,
                '', # country,
                '', # tel_cell || $per->tel_home || $per->tel_work,
                '', # sex,
                '', # comment
            ), "\n";

            my $cost = int($g->cost);

            # concoct a transaction? - even though we don't
            # have the individual transaction?

            # TRANSACTION (amount due in the grid but not collected)
            # we DO collect the *total* of all of these costs
            # from the rental coordinator - plus other costs
            # such as meeting place, extra time fees, etc.
        }

    }
    close $prog;
    close $reg;
    close $trans;
}

sub mmc_rg_export : Local {
    my ($self, $c) = @_;
    
    system("cd $dir; rm *.csv");    # clear the field
    _gen_csv($c);
    system("cd $dir; tar cvf $fname *.csv");
    #ZIP system("cd $dir; zip $fname *.csv");
    open my $fh, '<', "$dir/$fname"
        or die "$fname not found!!: $!\n";
    $c->response->content_type('application/x-tar');
    #ZIP $c->response->content_type('application/x-zip');
    #ZIP  it downloads on OSX as mmc_rg_export not mmc_rg_export.zip
    #ZIP  it IS a .zip file
    $c->response->body($fh);
}

1;
