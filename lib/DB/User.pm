use strict;
use warnings;
package DB::User;
use DBH;

sub order { 2 }     # needs Role

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS user;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE user (
id integer primary key auto_increment,
username varchar(15),
password varchar(255),
email varchar(100),
first varchar(30),
last varchar(30),
bg char(15),
fg char(15),
link char(15),
office varchar(15),
cell varchar(15),
txt_msg_email varchar(30),
hide_mmi char(3),
locked char(3),
expiry_date char(8),
nfails tinyint,
last_login_date char(8) 
)
EOS
}

sub init {
    my ($class, $today, $email) = @_;
    my $roles_sth = $dbh->prepare(<<"EOS");
SELECT id, role
  FROM role
EOS
    $roles_sth->execute();
    my %id_for;
    while (my ($id, $role) = $roles_sth->fetchrow_array()) {
        $id_for{$role} = $id;
    }
    my $add_role_sth = $dbh->prepare(<<"EOS");
INSERT INTO user_role
(user_id, role_id)
VALUES
(?, ?);
EOS
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO user
(username, password, email, first, last, bg, fg, link, office, cell, txt_msg_email, hide_mmi, locked, expiry_date, nfails, last_login_date) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my (@fields) = split /\|/, $line, -1;
        my $user = $fields[0];
        # password (hashed)
        $fields[1] = ($user eq 'calendar')?
            'd05ab7aff9d8000ae1075ee1f4c8f93fe7428c2c977f24a7bcf63d6bbb89a91c'
                    # z2A2
           :'15794f8f66f752e17431c19561406a7373189242c05a9648e8da2c44aa23e922';
                    # helloA!1
        $fields[2] = $email;     # email

        # bg, fg, link - a somewhat obsolete feature
        $fields[5] = '255, 255, 255';
        $fields[6] = '  0,   0,   0';
        $fields[7] = '  0,   0, 255';

        $fields[-4] = '';                  # locked
        $fields[-3] = '21991231';          # expiry_date
        $fields[-2] = 0;                   # nfails
        $fields[-1] = ($today-1)->as_d8(); # last_login_date
        $sth->execute(@fields);
        my $user_id = $dbh->last_insert_id(undef, undef, undef, undef);
        my @roles;
        if ($user eq 'sahadev') {
            # assign ALL roles
            @roles = keys %id_for;
        }
        elsif ($user eq 'jayanti') {
            # registrar
            @roles = qw/
                prog_admin prog_staff
                mail_admin mail_staff
                mmi_admin
                user_admin
                event_scheduler
                time_traveler
            /;
        }
        elsif ($user eq 'susan') {
            # reception
            @roles = qw/
                mail_admin mail_staff
                field_staff
                member_admin
            /;
        }
        elsif ($user eq 'fieldstaff') {
            # field staff
            @roles = qw/
                field_staff
                prog_staff
            /;
        }
        for my $role (@roles) {
            $add_role_sth->execute($user_id, $id_for{$role});
        }
    }
}

1;

__DATA__
sahadev|1234|jon@suecenter.org|Jon|Bjornstad|||||||||20180814|0|20180708
jayanti|1234|jon@suecenter.org|Jayanti|Peterson|||||||||20180814|0|20180708
susan|1234|jon@suecenter.org|Susan|Robeck|||||||||20180814|0|20180708
fieldstaff|1234|jon@suecenter.org|Field|Staff|||||||||20180814|0|20180708
calendar|1234|jon@logicalpoetry.com|cal_first|cal_last|||||||||20180210|0|20180101
