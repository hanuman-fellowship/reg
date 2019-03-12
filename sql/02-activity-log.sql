DROP TABLE IF EXISTS activity;
CREATE TABLE activity (
  id integer primary key auto_increment,
  message varchar(256) NOT NULL,
  cdate varchar(8) NOT NULL,
  ctime varchar(4) NOT NULL
);

create index activity_cdate_ctime_idx on activity (cdate,ctime);
