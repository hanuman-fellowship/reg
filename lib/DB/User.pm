use strict;
use warnings;
package DB::User;
use DBH '$dbh';

sub order { 2 }     # needs Role

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS user;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE user (
id integer primary key autoincrement,
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
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO user
(username, password, email, first, last, bg, fg, link, office, cell, txt_msg_email, hide_mmi, locked, expiry_date, nfails, last_login_date) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my (@fields) = split /\|/, $line, -1;
        $sth->execute(@fields);
    }
}

1;

__DATA__
sahadev|15794f8f66f752e17431c19561406a7373189242c05a9648e8da2c44aa23e922|jon@suecenter.org|Jon|Bjornstad|||||||||20180814|0|20180708
brajesh|e451adc585d28056cb377beaf54e843c03b0f7485031f5a86b8e72a22d202a06|jon@suecenter.org|Brajesh|Friedberg|||||||||20180714|0|20180515
jamal|2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824|jon.bjornstad@gmail.com|Jamal|Killou||||123|456-090-9991||||20180210|0|20180218
jayanti|2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824|jayanti@mountmadonna.org|Jayanti|Peterson|||||||||20180210|0|20180101
lori|2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824|lori_march@hotmail.com|Lori|March|||||||||20180210|0|20180101
sukhdev|e451adc585d28056cb377beaf54e843c03b0f7485031f5a86b8e72a22d202a06|sukhdev@mountmadonna.org|Sukhdev|Pettingill|||||||||20180408|0|20180218
barnaby|2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824|barnaby@mountmadonna.org|Barnaby|Stamm|||||||||20180201|0|20180207
savita|2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824|savita@mountmadonna.org|Savita|Brownfield|||||||||20180131|0|20180218
sunanda|2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824|sunanda@mountmadonna.org|Sunanda|Pacey|||||||||20180201|0|20180207
calendar|2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824|jon@logicalpoetry.com|cal_first|cal_last|||||||||20180210|0|20180101
