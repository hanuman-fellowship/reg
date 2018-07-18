use strict;
use warnings;
package DB::Person;
use DBH '$dbh';

sub order { 2 }     # needs Affils

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS people;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE people (
id integer primary key autoincrement,
last varchar(255),
first varchar(255),
sanskrit varchar(255),
addr1 varchar(255),
addr2 varchar(255),
city varchar(255),
st_prov char(255),
zip_post char(255),
country varchar(255),
akey varchar(255),
tel_home varchar(255),
tel_work varchar(255),
tel_cell varchar(255),
email varchar(255),
sex char(1),
id_sps integer,
date_updat char(8),
date_entrd char(8),
comment varchar(512),
e_mailings char(3),
snail_mailings char(3),
share_mailings char(3),
deceased char(3),
inactive char(3),
safety_form char(3),
secure_code char(6),
temple_id integer,
waiver_signed char(3),
only_temple char(3)
)
EOS
}

sub init {
    my ($class, $today, $email) = @_;
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO people
(last, first, sanskrit, addr1, addr2, city, st_prov, zip_post, country, akey, tel_home, tel_work, tel_cell, email, sex, id_sps, date_updat, date_entrd, comment, e_mailings, snail_mailings, share_mailings, deceased, inactive, safety_form, secure_code, temple_id, waiver_signed, only_temple) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my (@fields) = split /\|/, $line, -1;
        $fields[13] = $email;
        $sth->execute(@fields);
    }
}

1;

__DATA__
Keizer|Willa||P.O.Box 538||Aromas|CA|95004|United States|53895004POB||||willa@homeopathyhome.net|F||20130718||marked||||||yes|RNRDWJ|||
Devi|Christine||6302 HarperPl. N.E #214||Albuquerque|NM|87109||630221487109HAR|123-123-1234||||F||20130718||marked|||||||SURRRL|||
Ashar|Vijay||528 Lisa Lane||San Jose|CA|95134|USA|52895134LIS||||bhakta711@yahoo.com|M||20150317||marked|||||||GNQMFO|||
Beck|Carmela||1156 High Street|#41|Santa Cruz|CA|95064|USA|11564195064HIG||||carmelitabeck@yahoo.com|F||20130720||marked|||yes||||MJQZDM|||
Lord|Christina||PO Box 693||Tesuque|NM|87574|USA|69387574POB||||jon@suecenter.org|F||20180322||marked||yes|||||KITHZE|||
Grivas|Channing||||littleton|CO|80130|usa|80130|||||F||20130718||marked|||||||RMPTHH|||
Esparza|Stephanie||14989 Redwood ln.||CHINO Hills|CA|91709|usa|1498991709RED|999-098-0987|||jon@suecenter.org|F||20180605||marked|yes|yes|||||OTMYTV|||
Belgin|Diana||348 Los Robles Road||Soquel|CA|95073|USA|34895073LOS||||dbelgin@yahoo.com|F||20130718||marked|||||||UVWEMY|||
McCall|Dona||3977 Jefferson Ave||Emerald Hills|CA|94062|USA|397794062JEF||||donamccall@yahoo.com|M||20130720||marked||yes|yes||||CJRMJT|||
Nayak|Smt Promodini||Arobindonagar-2ndlane||berhampur|ORISSA|760001|India|2760001ARO|||||F||20130718||marked|||||||VUWAGW|||
Assalian|Andrew||addr1|addr2|city|STPROV|ZC90|belgique|1290ADD|1h|2w|3c|druya1@yahoo.com|M||20130718||marked|yes||yes||||HZFZVO|||
Giufre|Elizabeth||199 Bonniebrook Road||Butler|PA|16002|USA|19916002BON||||elizag@zoominternet.net|F||20130718||marked|||||||PCTQZR|||
Bryant|Anumati Rachel||498 Fairbanks Ave||Oakland|CA|94610|USA|49894610FAI||||florbella@earthlink.net|F||20160124||marked|||||||CIUDOF||yes|
Eagles|Gabrielle||4606 Canada Way||Burnaby|BC|V5G 1K5|Canada|4606515CAN||||geagles@cantest.com|F||20130719||marked|yes||||||CQPOCM|||
Singer|Gigi||8501 east alameda ave. #615||denver|CO|80230|usa|850161580230EAS|||||F||20130718||marked|||||||NLQVJE|||
Hegstad|Susan||222 N. 2nd St. Ste 102||Boise|ID|83702|USA|222210283702NND|||||F||20130718||marked|||||||UYWIXF|||
Hill|Hollie||2725 Alma Street||Palo Alto|CA|94306||272594306ALM|||898-098-5432|jon@suecenter.org|F||20180616||marked|||||||BEVUUL|||
Grant|Heather||2792 Dollarton Hwy||North Vancouver|BC|V7H1A8|Canada|2792718DOL|678-098-1238|||jon@suecenter.org|M||20180321||marked|||||||EWBZIH|||
Poulos|Val||1425 PLUMAS ST||RENO|NV|89509|USA|142589509PLU|||||M||20180616||marked|||||||PQXSES|||
Jaros|Jennifer||PO Box 234||Ketchum|ID|83340|USA|23483340POB||||jon@suecenter.org|F||20180322||marked|||||||BBZOXB|||
Gorman|Lisa Marie||28191 Via Luis||Laguna Niguel|CA|92677|USA|2819192677VIA|123-908-8765|||jon@suecenter.org|F||20180321||marked|||||||DUDHCV|||
Battistoni|Kathy||1 Fairway Lane||Duxbury|MA|02332||102332FAI|123-123-1234|||jon@suecenter.org|F||20180321||marked|||||||ETEAUG|||
Borowski|Kimberly||616 Brookmere Ave. #4||Tipp City|OH|45371|United States|616445371BRO||||kima_bliss@live.com|F||20130718||marked|yes|yes|yes||||QMYQVO|||
Ertelt|Kim||2514 Gates Ave # A||Redondo Beach|CA|90278|USA|251490278GAT||||kimertelt@hotmail.com|F||20130718||marked|||||||CAKCHY|||
Ritso|Lori||P.O.Box 548||Redwood Estates|CA|95044|USA|54895044POB|||||F||20130718||marked|||||||ZGQEWV|||
Griffith|Neysa||701 beach street #301||santa cruz|CA|95060|usa|70130195060BEA||||jon@suecenter.org|F||20150315||marked|||||||UPBHJR|||
Joubert|Marlize||1337 stanford street||santa monica|CA|90404|usa|133790404STA||||jon@suecenter.org|M||20180616||marked|||||||PLDOLM|||
Galvin|Jennifer||703 Windsor St.||Santa Cruz|CA|95062||70395062WIN|||999-000-8888|jon@suecenter.org|F||20150316||marked|||||||IMOBEE|||
O'Donnell|Jennifer||251 El Sereno Drive||Scotts Valley|CA|95066|USA|25195066ELS|||||F||20131114||marked|||||||TKKBWN|||
Hegenbart|Naomi||414 Olive Street||Santa Cruz|CA|95060|United States|41495060OLI||||jon@suecenter.org|F||20150328||marked|||||||EAFJJS|||
Geracoulis|Mischa||1155 N. Cedar Street||Glendale|CA|91207|USA|115591207NCE|123-098-1324||||F||20170220||marked|||||||MUUXGH|||
Nicholson|Patricia||38999 sunnyfield drive||merced|CA|95340|usa|3899995340SUN|456-2|789-9|123-1|patricia_nicholson@comcast.net|F||20130718||marked|yes|yes|||||QHZLYP|||
Trujillo|Tamara||9931 Aftonwood St||Highlands Ranch|CO|80126|USA|993180126AFT||||shoresdesante@yahoo.com|F||20130718||marked|||||||KNFBZS|||
Farwell|Troy||112 west caroline st||fenton|MI|48430|usa|11248430WES|||||M||20171225||marked|||||||XWGWXY|||
Wilson|April||||||||||||snowcrane@gmail.com|F||20130718||marked|||||||XWCCVK|||
Zay|Sabra||2815 S. Nettleton #109||Spfd|MO|65807|usa|281510965807SNE||||jon@suecenter.org|F||20180322||marked|||||||FZOEBB|||
Burton|Sumitra||445 Summit Road||Watsonville|CA|95076|USA|44595076SUM|333-000-9191|||jon@suecenter.org|F||20180501||marked|||||yes||UHRVAH|||
Haycraft|Trista||p.o. box 82756||fairbanks|AL|99708|usa|8275699708POB||||jon@suecenter.org|F||20170323||marked||yes|||||TZCIDA|||
Rowlandson|Zoe||421 9th Avenue||Santa Cruz|CA|95060|USA|421995060THA||||jon@suecenter.org|F||20180406||marked|||||||JPCMRS|||
Withers|Kate||PO Box 205||Marysville|PA|17053||20517053POB|||111-222-9999|kwithers99@hotmail.com|F||20170707|20110316|marked|yes||yes||||ZEJTJS|||
Saji|Sarkawi||Tamantas 2 Jalan 42||Kuantan|PAH DM|25150|Malaysia|24225150TAM|60 016 9800352|||jon@suecenter.org|M||20150316|20110318|marked|yes|yes|yes||||SVPJHG|||
Vanover|Debra||1720 Shuler Ave||Hamilton|OH|45011||172045011SHU|513-875-8127|||jon@suecenter.org|F||20130718|20110318|marked|yes|yes|yes||||NQKIOM|||
Estrada|Karla||35 Calle Nube 4| Sm 3 M  5 Retorno|Cancun|Quintana Roo|77500|Mexico|3543577500CAL||||karla_cu13@hotmail.com|F||20130720|20110318|marked|yes||yes||||EBZDYY|||
Jones|Kat||8103 Ashley Circle Dr S||Houston|TX|77071||810377071ASH|713-777-0877|||katfalnjones@comcast.com|F||20160703|20110318|marked|yes|yes|yes||yes|yes|JVNQMA|||
Killou|Jamal|||||||||||||M||20130718|20110406|marked|yes|yes|yes||||XXHNRK|||
Gaulois|Madame||1155 N cedilla||blah|MA|91207||115591207NCE|||||F||20130718|20110406|marked|yes|yes|yes||||GYDRFK|||
Peterson|Jayanti||123 st||doylestown|PA|95076||12395076ST||||jayanti@mountmadonna.org|F|0|20130718|20111027|marked||yes|||||ADAPCH|||
Frost|Jennifer||808 Delaware Street||Watsonville|CA|95076||80895076DEL|831-320-8326|||jon@suecenter.org|F|0|20180322|20111027|marked|||||||ZHYEVV|||
Johhsen|Blehnam||123 Main||Santa Cruz|CA|||123MAI||123-109-0102|||M||20170220|20130320|marked|yes|yes|yes||||QBRTQK|||
Whipple|Laura||752 N. McCadden Place||Los Angeles|CA|90038||75290038NMC|323-466-3609|||whipple0@gmail.com|F|0|20130718|20130617|marked|yes||yes||||UVXLLI|||
Reese|Morgan||684 chiquita ave #B||mountain view|ca|94041||68494041CHI|201-290-7355|||earthstroll@yahoo.com|M|0|20131005|20131005|marked|||||||OTKLHY|||
Frank|Jarly||808 Delaware Street||Watsonville|CA|95076||80895076DEL|831-320-8326|||jon@suecenter.org|F|0|20180321|20131005|marked|||||||JNGFBO|||
Neilson|Gregg||200 Valparaiso Ave||Cotati|CA|94931||20094931VAL|||707-848-2414|jon@suecenter.org|M||20150315|20131221|marked|yes||||||XGYKSQ|||
Beahan|Francis||PO Box 1699||Santa Cruz|CA|95061||169995061POB|||831-459-3950|frankjbn@gmail.com|M|0|20170702|20150808||yes|yes|yes||||XASUYT|0||
Degenaro|Tiki||RR 2 BOX 4500||PAHOA|HI|96778||2450096778RRB|650-743-0958|808-965-0468|650-743-0958|tiki@kalani.com|F|0|20150928|20150808||yes|yes|1||||GDBJWE|0||
Aubry|Mary||420 7th ST NW, Apt. # 826||Washington|DC|20004||420782620004THS|202-731-2174|202-208-6721|202-731-2174|mary.aubry@gmail.com|F|0|20150929|20150929||||||||TQEROZ|0||
Beahan|Francione||PO Box 1699||Santa Cruz|CA|95061||169995061POB|||831-459-3950|frankjbn@gmail.com|M|0|20160124|20160124||||||||XQVJSF|0|yes|
Sandecki|Dana||234 Strawberry Field Rd||Warwick|RI|02886-9670||9117811HEL|||408-908-1223|lalita2000@earthlink.net|F|0|20170108|20151025||yes||||||THLBXP|0||
