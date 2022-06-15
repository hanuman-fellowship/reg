#!/usr/bin/env perl
use strict;
use warnings;
use CGI;
my $q = CGI->new();
print $q->header();
use Template;
use lib '../lib';
use Date::Simple qw/
    today
/;
use Time::Simple qw/
    get_time
/;
use Util qw/
    db_init
    model
    email_letter
/;
use Global qw/
    %string
/;
my $c = db_init();
Global->init($c, 1, 1);     # to get %strings:

my %param = %{ $q->Vars() };
for my $n (qw/ description what_else /) {
    $param{$n} =~ s{\n}{<br>}xmsg;
}
if ($param{leader_name}) {
    for my $f (keys %param) {
        if ($param{$f} =~ m{\0}xms) {
            my @arr = split "\0", $param{$f};
            my $key = "other_$f";
            if ($param{$key}) {
                push @arr, $param{$key};
            }
            $param{$f} = join(', ', @arr);
        }
    }
    delete $param{other_needs};
    delete $param{other_retreat_type};
    my $inquiry = model($c, 'Inquiry')->create({
        the_date => today()->as_d8(),
        the_time => get_time->t24(),
        %param,
    });
    my $inq_id = $inquiry->id();
    $param{inquiry_id} = $inq_id;
    my $html;
    Template->new(INTERPOLATE => 1)->process(
        'program_inquiry.tt2',
        \%param,
        \$html,
    );
    email_letter($c,
        from    => 'notifications@mountmadonna.org',
        to      => $string{program_inquiry_email},
        cc      => "$param{leader_name} <$param{email}>",
        subject => "Program Inquiry from $param{leader_name}",
        html    => $html,
        activity_msg => "Program Inquiry by <a href='/inquiry/view/$inq_id'>$param{leader_name}</a>",
    );
    print "<div style='font-size: 18pt; margin: .5in; font-family: Arial'>Thank you.  We will be in touch.</div>\n";
}
else {
    print <<'EOH';
<html>
<head>
<style>
body {
    margin: .5in
}
body, input, textarea, .submit, option, select {
    font-size: 18pt;
    font-family: Arial;
}
.required {
    color: red;
    font-size: 24pt;
}
.submit {
    background: lightgreen;
}
</style>
<script>
var fields = [
    { id: 'leader_name', regexp: '\\S',
                    err: 'Missing Leader Name' },
    { id: 'phone',  regexp: '^[0-9 -.()]+$',
                    err: 'Invalid Phone number' },
    { id: 'email',  regexp: '^\\s*\\S+@\\S+\\s*$',
                    err: 'Invalid Email address' },
    { id: 'group_name',  regexp: '\\S',
                         err: 'Missing Group Name' },
    { id: 'dates',  regexp: '\\S',
                    err: 'Missing Dates' },
    { id: 'radio', name: 'how_many',   err: 'How many participants?' },
    { id: 'radio', name: 'vegetarian', err: 'Is vegetarian food okay for you?' },
    { id: 'learn',  regexp: '\\S',
                    err: 'Missing How did you learn about Mount Madonna?' }
];
function check_fields() {
    var mess = '';
    var focus = 0;
    for (f in fields) {
        fld = fields[f];
        if (fld.id === 'radio') {
            var chk = document.querySelector(
                          'input[name="'
                          + fld.name
                          + '"]:checked'
                      );
            if (chk == null) {
                if (focus == 0) {
                    document.getElementsByName(fld.name)[0].focus();
                    focus = 1;
                }
                mess += fld.err + '\n';
            }
        }
        else {
            var el = document.getElementById(fld.id);
            var regexp = new RegExp(fld.regexp);
            if (! regexp.test(el.value)) {
                mess += fld.err + '\n';
                if (focus == 0 ){
                    focus = 1;
                    el.focus();
                }
            }
        }
    }
    if (mess === '') {
        return true;
    }
    else {
        alert(mess);
        return false;
    }
}
</script>
</head>
<body>
<img src='https://www.mountmadonna.org/assets/img/logo/mmc-teal.png' width=400>
<br>
<h1>Program Inquiry Form</h1>
<form action='https://akash.mountmadonna.org/cgi-bin/program_inquiry.pl'
      method=POST
      onsubmit='return check_fields();'
>
Fill out the form below and we will be in touch with you soon.
<p>
<span class=required>*</span> indicates fields that are required
<p>
Name of Group Leader <span class=required>*</span><br>
<input type=text size=45 name=leader_name id=leader_name><p>
Contact phone number <span class=required>*</span><br>
<input type=text size=45 name=phone id=phone><p>
Contact email address <span class=required>*</span><br>
<input type=text size=45 name=email id=email><p>
Name of Group <span class=required>*</span><br>
<input type=text size=45 name=group_name id=group_name><p>
What dates are you contemplating? <span class=required>*</span><br>
<input type=text size=45 name=dates id=dates><p>
Short description of retreat<br>
<textarea name=description rows=4 cols=48>
</textarea>
<p>
How many participants do you anticipate? <span class=required>*</span><br>
<ul>
<input type=radio name=how_many value='20-25'> 20-25<br>
<input type=radio name=how_many value='25-40'> 25-40<br>
<input type=radio name=how_many value='40-60'> 40-60<br>
<input type=radio name=how_many value='60-80'> 60-80<br>
<input type=radio name=how_many value='80-100'> 80-100<br>
<input type=radio name=how_many value='100-150'> 100-150<br>
<input type=radio name=how_many value='150+'> 150+<br>
</ul>
<p>
Mount Madonna Center is a strict vegetarian community.<br>
Is that okay with you? <span class=required>*</span><br>
<ul>
<input type=radio name=vegetarian value='Yes'>Yes<br>
<input type=radio name=vegetarian value='NO'>No<br>
</ul>
<p>
Retreat Type<br>
<ul>
<input type=checkbox name=retreat_type value='Yoga retreat'> Yoga retreat<br>
<input type=checkbox name=retreat_type value='Meditation retreat'> Meditation retreat<br>
<input type=checkbox name=retreat_type value='Offsite business retreat'> Offsite business retreat<br>
<input type=checkbox name=retreat_type value='Educational training'> Educational training<br>
Other: <input type=text size=33 name=other_retreat_type>
<br>
</ul>
<p>
What needs do you have?<br>
<ul>
<input type=checkbox name=needs value='Yoga props'> Yoga props<br>
<input type=checkbox name=needs value='Wifi'> Wifi<br>
<input type=checkbox name=needs value='Massage tables'> Massage tables<br>
<input type=checkbox name=needs value='Projector and screen'> Projector and screen<br>
<input type=checkbox name=needs value='Audio setup'> Audio setup<br>
Other: <input type=text size=33 name=other_needs>
</ul>
<p> 
How did you learn about Mount Madonna Center? <span class=required>*</span><br>
<input type=text size=45 name=learn id=learn><p>
<p>
Anything else we should know?<br>
<textarea name=what_else rows=4 cols=48>
</textarea>
<p>
<input style="background: lightgreen" type=submit value='Submit'>
</form>
<script>document.getElementById('leader_name').focus();</script>
EOH
}
