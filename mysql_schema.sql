-- MySQL dump 10.11
--
-- Host: localhost    Database: reg2
-- ------------------------------------------------------
-- Server version	5.0.95

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `affil_people`
--

DROP TABLE IF EXISTS `affil_people`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `affil_people` (
  `a_id` int(11) default NULL,
  `p_id` int(11) default NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `affil_program`
--

DROP TABLE IF EXISTS `affil_program`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `affil_program` (
  `a_id` int(11) default NULL,
  `p_id` int(11) default NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `affil_reports`
--

DROP TABLE IF EXISTS `affil_reports`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `affil_reports` (
  `report_id` int(11) default NULL,
  `affiliation_id` int(11) default NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `affils`
--

DROP TABLE IF EXISTS `affils`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `affils` (
  `id` int(11) NOT NULL auto_increment,
  `descrip` text,
  `system` text NOT NULL,
  `selectable` text NOT NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=98 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `annotation`
--

DROP TABLE IF EXISTS `annotation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `annotation` (
  `id` int(11) NOT NULL auto_increment,
  `cluster_type` text,
  `label` text,
  `x` int(11) default NULL,
  `y` int(11) default NULL,
  `x1` int(11) default NULL,
  `y1` int(11) default NULL,
  `x2` int(11) default NULL,
  `y2` int(11) default NULL,
  `shape` text,
  `thickness` int(11) default NULL,
  `color` text,
  `inactive` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=59 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `block`
--

DROP TABLE IF EXISTS `block`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `block` (
  `id` int(11) NOT NULL auto_increment,
  `house_id` int(11) default NULL,
  `sdate` text,
  `edate` text,
  `nbeds` int(11) default NULL,
  `reason` text,
  `user_id` int(11) default NULL,
  `the_date` text,
  `time` text,
  `comment` text,
  `allocated` text,
  `npeople` int(11) default NULL,
  `event_id` int(11) default NULL,
  `program_id` int(11) default NULL,
  `rental_id` int(11) default NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=11363 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `book`
--

DROP TABLE IF EXISTS `book`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `book` (
  `id` int(11) NOT NULL auto_increment,
  `title` text,
  `author` text,
  `publisher` text,
  `description` text,
  `location` text,
  `subject` text,
  `media` int(11) default NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=5516 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `booking`
--

DROP TABLE IF EXISTS `booking`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `booking` (
  `id` int(11) NOT NULL auto_increment,
  `meet_id` int(11) default NULL,
  `rental_id` int(11) default NULL,
  `program_id` int(11) default NULL,
  `event_id` int(11) default NULL,
  `sdate` text,
  `edate` text,
  `breakout` text,
  `dorm` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=5692 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `canpol`
--

DROP TABLE IF EXISTS `canpol`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `canpol` (
  `id` int(11) NOT NULL auto_increment,
  `name` text,
  `policy` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=27 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `category`
--

DROP TABLE IF EXISTS `category`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `category` (
  `id` int(11) NOT NULL auto_increment,
  `name` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=8 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `check_out`
--

DROP TABLE IF EXISTS `check_out`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `check_out` (
  `book_id` int(11) default NULL,
  `person_id` int(11) default NULL,
  `due_date` text
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `cluster`
--

DROP TABLE IF EXISTS `cluster`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cluster` (
  `id` int(11) NOT NULL auto_increment,
  `name` text,
  `type` text,
  `cl_order` int(11) default '0',
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=26 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `conf_history`
--

DROP TABLE IF EXISTS `conf_history`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `conf_history` (
  `id` int(11) NOT NULL auto_increment,
  `reg_id` int(11) default NULL,
  `note` text,
  `user_id` int(11) default NULL,
  `the_date` text,
  `time` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=27825 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `config`
--

DROP TABLE IF EXISTS `config`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `config` (
  `house_id` int(11) default NULL,
  `the_date` text,
  `sex` text,
  `curmax` int(11) default NULL,
  `cur` int(11) default NULL,
  `program_id` int(11) default NULL,
  `rental_id` int(11) default NULL,
  KEY `i_config` (`house_id`,`the_date`(8))
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `confnote`
--

DROP TABLE IF EXISTS `confnote`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `confnote` (
  `id` int(11) NOT NULL auto_increment,
  `abbr` text,
  `expansion` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=121 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `credit`
--

DROP TABLE IF EXISTS `credit`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `credit` (
  `id` int(11) NOT NULL auto_increment,
  `person_id` int(11) default NULL,
  `reg_id` int(11) default NULL,
  `date_given` text,
  `amount` int(11) default NULL,
  `date_expires` text,
  `date_used` text,
  `used_reg_id` int(11) default NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=1054 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `deposit`
--

DROP TABLE IF EXISTS `deposit`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `deposit` (
  `id` int(11) NOT NULL auto_increment,
  `user_id` int(11) default NULL,
  `date_start` text,
  `date_end` text,
  `time` text,
  `cash` decimal(8,2) default NULL,
  `chk` decimal(8,2) default NULL,
  `credit` decimal(8,2) default NULL,
  `online` decimal(8,2) default NULL,
  `sponsor` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=1582 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `donation`
--

DROP TABLE IF EXISTS `donation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `donation` (
  `id` int(11) NOT NULL auto_increment,
  `person_id` int(11) default NULL,
  `project_id` int(11) default NULL,
  `the_date` text,
  `amount` int(11) default NULL,
  `type` text,
  `who_d` int(11) default NULL,
  `date_d` text,
  `time_d` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=96 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `event`
--

DROP TABLE IF EXISTS `event`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `event` (
  `id` int(11) NOT NULL auto_increment,
  `name` text,
  `descr` text,
  `sdate` text,
  `edate` text,
  `sponsor` text,
  `max` text,
  `organization_id` int(11) NOT NULL,
  `pr_alert` text,
  `user_id` int(11) NOT NULL default '0',
  `the_date` text NOT NULL,
  `time` text NOT NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=1438 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `exception`
--

DROP TABLE IF EXISTS `exception`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `exception` (
  `prog_id` int(11) default NULL,
  `tag` text,
  `value` text
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `glossary`
--

DROP TABLE IF EXISTS `glossary`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `glossary` (
  `term` text,
  `definition` text
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `house`
--

DROP TABLE IF EXISTS `house`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `house` (
  `id` int(11) NOT NULL auto_increment,
  `name` text,
  `max` int(11) default NULL,
  `bath` text,
  `tent` text,
  `center` text,
  `cabin` text,
  `priority` int(11) default NULL,
  `x` int(11) default NULL,
  `y` int(11) default NULL,
  `cluster_id` int(11) default NULL,
  `cluster_order` int(11) default NULL,
  `inactive` text,
  `disp_code` text,
  `comment` text,
  `resident` text,
  `cat_abode` text,
  `sq_foot` text,
  `key_card` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=299 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `housecost`
--

DROP TABLE IF EXISTS `housecost`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `housecost` (
  `id` int(11) NOT NULL auto_increment,
  `name` text,
  `single_bath` int(11) default NULL,
  `single` int(11) default NULL,
  `dble_bath` int(11) default NULL,
  `dble` int(11) default NULL,
  `triple` int(11) default NULL,
  `dormitory` int(11) default NULL,
  `economy` int(11) default NULL,
  `center_tent` int(11) default NULL,
  `own_tent` int(11) default NULL,
  `own_van` int(11) default NULL,
  `commuting` int(11) default NULL,
  `type` text,
  `inactive` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=136 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `issue`
--

DROP TABLE IF EXISTS `issue`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `issue` (
  `id` int(11) NOT NULL auto_increment,
  `priority` text,
  `title` text,
  `notes` text,
  `date_entered` text,
  `date_closed` text,
  `user_id` int(11) default NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=613 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `leader`
--

DROP TABLE IF EXISTS `leader`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `leader` (
  `id` int(11) NOT NULL auto_increment,
  `person_id` int(11) default NULL,
  `public_email` text,
  `url` text,
  `image` text,
  `biography` text,
  `assistant` text,
  `l_order` int(11) default NULL,
  `just_first` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=418 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `leader_program`
--

DROP TABLE IF EXISTS `leader_program`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `leader_program` (
  `l_id` int(11) default NULL,
  `p_id` int(11) default NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `level`
--

DROP TABLE IF EXISTS `level`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `level` (
  `id` int(11) NOT NULL auto_increment,
  `name` text,
  `long_term` text,
  `public` text,
  `school_id` int(11) default NULL,
  `name_regex` text,
  `glnum_suffix` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=16 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `make_up`
--

DROP TABLE IF EXISTS `make_up`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `make_up` (
  `house_id` int(11) NOT NULL,
  `date_vacated` text,
  `date_needed` text,
  `refresh` text,
  PRIMARY KEY  (`house_id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `meal`
--

DROP TABLE IF EXISTS `meal`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `meal` (
  `id` int(11) NOT NULL auto_increment,
  `sdate` text,
  `edate` text,
  `breakfast` int(11) default NULL,
  `lunch` int(11) default NULL,
  `dinner` int(11) default NULL,
  `comment` text,
  `user_id` int(11) default NULL,
  `the_date` text,
  `time` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `meeting_place`
--

DROP TABLE IF EXISTS `meeting_place`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `meeting_place` (
  `id` int(11) NOT NULL auto_increment,
  `abbr` text,
  `name` text,
  `max` int(11) default NULL,
  `disp_ord` int(11) default NULL,
  `color` text,
  `sleep_too` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=29 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `member`
--

DROP TABLE IF EXISTS `member`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `member` (
  `id` int(11) NOT NULL auto_increment,
  `person_id` int(11) default NULL,
  `category` text,
  `date_general` text,
  `date_sponsor` text,
  `sponsor_nights` int(11) default NULL,
  `date_life` text,
  `free_prog_taken` text,
  `total_paid` int(11) default NULL,
  `voter` text NOT NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=532 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `mmi_payment`
--

DROP TABLE IF EXISTS `mmi_payment`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `mmi_payment` (
  `id` int(11) NOT NULL auto_increment,
  `person_id` int(11) default NULL,
  `amount` decimal(8,2) default NULL,
  `glnum` text,
  `the_date` text,
  `type` text,
  `deleted` text,
  `reg_id` int(11) default NULL,
  `note` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=23012 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `night_hist`
--

DROP TABLE IF EXISTS `night_hist`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `night_hist` (
  `id` int(11) NOT NULL auto_increment,
  `member_id` int(11) default NULL,
  `num_nights` int(11) default NULL,
  `action` text,
  `reg_id` int(11) default NULL,
  `user_id` int(11) default NULL,
  `the_date` text,
  `time` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=1230 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `organization`
--

DROP TABLE IF EXISTS `organization`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `organization` (
  `id` int(11) NOT NULL auto_increment,
  `name` varchar(30) NOT NULL,
  `on_prog_cal` varchar(3) NOT NULL default '',
  `color` varchar(13) default '255,255,255',
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=11 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `people`
--

DROP TABLE IF EXISTS `people`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `people` (
  `last` text,
  `first` text,
  `sanskrit` text,
  `addr1` text,
  `addr2` text,
  `city` text,
  `st_prov` text,
  `zip_post` text,
  `country` text,
  `akey` text,
  `tel_home` text,
  `tel_work` text,
  `tel_cell` text,
  `email` text,
  `sex` text,
  `id` int(11) NOT NULL auto_increment,
  `id_sps` int(11) default NULL,
  `date_updat` text,
  `date_entrd` text,
  `comment` text,
  `e_mailings` text NOT NULL,
  `snail_mailings` text NOT NULL,
  `share_mailings` text NOT NULL,
  `deceased` text NOT NULL,
  `inactive` text NOT NULL,
  `safety_form` text,
  `secure_code` text NOT NULL,
  `temple_id` int(11) default NULL,
  `waiver_signed` text,
  `only_temple` text,
  PRIMARY KEY  (`id`),
  KEY `i_last` (`last`(30)),
  KEY `i_akey` (`akey`(30)),
  KEY `i_sps` (`id_sps`)
) ENGINE=MyISAM AUTO_INCREMENT=262815 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `program`
--

DROP TABLE IF EXISTS `program`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `program` (
  `id` int(11) NOT NULL auto_increment,
  `name` text,
  `title` text,
  `subtitle` text,
  `glnum` text,
  `housecost_id` int(11) default NULL,
  `retreat` text,
  `sdate` text,
  `edate` text,
  `tuition` int(11) default NULL,
  `confnote` text,
  `url` text,
  `webdesc` text,
  `webready` text,
  `image` text,
  `kayakalpa` text,
  `canpol_id` int(11) default NULL,
  `extradays` int(11) default NULL,
  `full_tuition` int(11) default NULL,
  `deposit` int(11) default NULL,
  `collect_total` text,
  `linked` text,
  `unlinked_dir` text,
  `ptemplate` text,
  `cl_template` text,
  `sbath` text,
  `economy` text,
  `footnotes` text,
  `reg_start` text,
  `reg_end` text,
  `prog_start` text,
  `prog_end` text,
  `reg_count` int(11) default NULL,
  `lunches` text,
  `max` text,
  `notify_on_reg` text,
  `summary_id` int(11) default NULL,
  `rental_id` int(11) default NULL,
  `do_not_compute_costs` text,
  `dncc_why` text,
  `color` text,
  `single` text,
  `allow_dup_regs` text,
  `commuting` text,
  `percent_tuition` int(11) default NULL,
  `refresh_days` text,
  `category_id` int(11) default '0',
  `facebook_event_id` text NOT NULL,
  `not_on_calendar` text,
  `tub_swim` text,
  `cancelled` text NOT NULL,
  `pr_alert` text,
  `school_id` int(11) default NULL,
  `level_id` int(11) default NULL,
  `bank_account` text,
  `waiver_needed` text,
  `housing_not_needed` text,
  `req_pay` text NOT NULL,
  `program_created` text,
  `created_by` int(11) default '0',
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=4210 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `program_cluster`
--

DROP TABLE IF EXISTS `program_cluster`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `program_cluster` (
  `program_id` int(11) default NULL,
  `cluster_id` int(11) default NULL,
  `seq` int(11) default NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `program_doc`
--

DROP TABLE IF EXISTS `program_doc`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `program_doc` (
  `id` int(11) NOT NULL auto_increment,
  `program_id` int(11) NOT NULL,
  `title` text,
  `suffix` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=15 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `project`
--

DROP TABLE IF EXISTS `project`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `project` (
  `id` int(11) NOT NULL auto_increment,
  `descr` text,
  `glnum` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=6 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `proposal`
--

DROP TABLE IF EXISTS `proposal`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `proposal` (
  `id` int(11) NOT NULL auto_increment,
  `date_of_call` text,
  `group_name` text,
  `rental_type` text,
  `max` int(11) default NULL,
  `min` int(11) default NULL,
  `dates_requested` text,
  `checkin_time` text,
  `checkout_time` text,
  `other_things` text,
  `meeting_space` text,
  `housing_space` text,
  `leader_housing` text,
  `special_needs` text,
  `food_service` text,
  `other_requests` text,
  `program_meeting_date` text,
  `denied` text,
  `provisos` text,
  `first` text,
  `last` text,
  `addr1` text,
  `addr2` text,
  `city` text,
  `st_prov` text,
  `zip_post` text,
  `country` text,
  `tel_home` text,
  `tel_work` text,
  `tel_cell` text,
  `email` text,
  `cs_first` text,
  `cs_last` text,
  `cs_addr1` text,
  `cs_addr2` text,
  `cs_city` text,
  `cs_st_prov` text,
  `cs_zip_post` text,
  `cs_country` text,
  `cs_tel_home` text,
  `cs_tel_work` text,
  `cs_tel_cell` text,
  `cs_email` text,
  `deposit` int(11) default NULL,
  `misc_notes` text,
  `rental_id` int(11) default NULL,
  `person_id` int(11) default NULL,
  `cs_person_id` int(11) default NULL,
  `staff_ok` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=314 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `reg_charge`
--

DROP TABLE IF EXISTS `reg_charge`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `reg_charge` (
  `id` int(11) NOT NULL auto_increment,
  `reg_id` int(11) default NULL,
  `user_id` int(11) default NULL,
  `the_date` text,
  `time` text,
  `amount` decimal(8,2) default NULL,
  `what` text,
  `automatic` text,
  `type` int(11) default '5',
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=196674 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `reg_history`
--

DROP TABLE IF EXISTS `reg_history`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `reg_history` (
  `id` int(11) NOT NULL auto_increment,
  `reg_id` int(11) default NULL,
  `user_id` int(11) default NULL,
  `the_date` text,
  `time` text,
  `what` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=398711 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `reg_payment`
--

DROP TABLE IF EXISTS `reg_payment`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `reg_payment` (
  `id` int(11) NOT NULL auto_increment,
  `reg_id` int(11) default NULL,
  `user_id` int(11) default NULL,
  `the_date` text,
  `time` text,
  `amount` decimal(8,2) default NULL,
  `type` text,
  `what` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=119623 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `registration`
--

DROP TABLE IF EXISTS `registration`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `registration` (
  `id` int(11) NOT NULL auto_increment,
  `person_id` int(11) default NULL,
  `program_id` int(11) default NULL,
  `deposit` int(11) default NULL,
  `referral` text,
  `adsource` text,
  `kids` text,
  `comment` text,
  `confnote` text,
  `h_type` text,
  `h_name` text,
  `carpool` text,
  `hascar` text,
  `arrived` text,
  `cancelled` text,
  `date_postmark` text,
  `time_postmark` text,
  `balance` int(11) default NULL,
  `date_start` text,
  `date_end` text,
  `early` text,
  `late` text,
  `ceu_license` text,
  `letter_sent` text,
  `status` text,
  `nights_taken` int(11) default NULL,
  `free_prog_taken` text,
  `house_id` int(11) default NULL,
  `cabin_room` text,
  `leader_assistant` text,
  `pref1` text,
  `pref2` text,
  `share_first` text,
  `share_last` text,
  `manual` text,
  `work_study` text,
  `work_study_comment` text,
  `rental_before` text,
  `rental_after` text,
  `work_study_safety` text,
  `transaction_id` text NOT NULL,
  `from_where` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=92538 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `rental`
--

DROP TABLE IF EXISTS `rental`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `rental` (
  `id` int(11) NOT NULL auto_increment,
  `name` text,
  `title` text,
  `subtitle` text,
  `glnum` text,
  `sdate` text,
  `edate` text,
  `url` text,
  `webdesc` text,
  `linked` text,
  `phone` text,
  `email` text,
  `comment` text,
  `housecost_id` int(11) default NULL,
  `max` int(11) default NULL,
  `balance` decimal(8,2) default NULL,
  `contract_sent` text,
  `sent_by` text,
  `contract_received` text,
  `received_by` text,
  `tentative` text,
  `start_hour` text,
  `end_hour` text,
  `coordinator_id` int(11) default NULL,
  `cs_person_id` int(11) default NULL,
  `lunches` text,
  `status` text,
  `deposit` int(11) default NULL,
  `summary_id` int(11) default NULL,
  `mmc_does_reg` text,
  `program_id` int(11) default NULL,
  `proposal_id` int(11) default NULL,
  `color` text,
  `housing_note` text,
  `grid_code` text,
  `expected` int(11) default NULL,
  `staff_ok` text,
  `refresh_days` text,
  `rental_follows` text,
  `cancelled` text NOT NULL,
  `fixed_cost_houses` text,
  `fch_encoded` text,
  `grid_stale` text,
  `pr_alert` text,
  `arrangement_sent` text,
  `arrangement_by` text,
  `counts` text,
  `grid_max` int(11) default '0',
  `housing_charge` int(11) default '0',
  `rental_created` text,
  `created_by` int(11) default '0',
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=1522 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `rental_booking`
--

DROP TABLE IF EXISTS `rental_booking`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `rental_booking` (
  `rental_id` int(11) default NULL,
  `date_start` text,
  `date_end` text,
  `house_id` int(11) default NULL,
  `h_type` text
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `rental_charge`
--

DROP TABLE IF EXISTS `rental_charge`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `rental_charge` (
  `id` int(11) NOT NULL auto_increment,
  `rental_id` int(11) default NULL,
  `amount` decimal(8,2) default NULL,
  `what` text,
  `user_id` int(11) default NULL,
  `the_date` text,
  `time` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=1187 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `rental_cluster`
--

DROP TABLE IF EXISTS `rental_cluster`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `rental_cluster` (
  `rental_id` int(11) default NULL,
  `cluster_id` int(11) default NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `rental_payment`
--

DROP TABLE IF EXISTS `rental_payment`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `rental_payment` (
  `id` int(11) NOT NULL auto_increment,
  `rental_id` int(11) default NULL,
  `amount` decimal(8,2) default NULL,
  `type` text,
  `user_id` int(11) default NULL,
  `the_date` text,
  `time` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=1312 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `reports`
--

DROP TABLE IF EXISTS `reports`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `reports` (
  `id` int(11) NOT NULL auto_increment,
  `descrip` text,
  `rep_order` text,
  `zip_range` text,
  `format` int(11) default NULL,
  `nrecs` int(11) default NULL,
  `last_run` text,
  `update_cutoff` text NOT NULL,
  `end_update_cutoff` text NOT NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=174 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `req_payment`
--

DROP TABLE IF EXISTS `req_payment`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `req_payment` (
  `id` int(11) NOT NULL auto_increment,
  `org` text,
  `person_id` int(11) default '0',
  `amount` int(11) default '0',
  `for_what` int(11) default '0',
  `the_date` text,
  `reg_id` int(11) default '0',
  `note` text,
  `code` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=4648 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `resident`
--

DROP TABLE IF EXISTS `resident`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `resident` (
  `id` int(11) NOT NULL auto_increment,
  `person_id` int(11) default NULL,
  `comment` text,
  `image` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=44 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `resident_note`
--

DROP TABLE IF EXISTS `resident_note`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `resident_note` (
  `id` int(11) NOT NULL auto_increment,
  `resident_id` int(11) default NULL,
  `the_date` text,
  `the_time` text,
  `note` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=6 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ride`
--

DROP TABLE IF EXISTS `ride`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `ride` (
  `id` int(11) NOT NULL auto_increment,
  `rider_id` int(11) default NULL,
  `driver_id` int(11) default NULL,
  `from_to` text,
  `pickup_date` text,
  `airport` text,
  `carrier` text,
  `flight_num` text,
  `flight_time` text,
  `cost` decimal(8,2) default NULL,
  `comment` text,
  `paid_date` text,
  `sent_date` text,
  `type` text,
  `shuttle` int(11) default NULL,
  `pickup_time` text,
  `create_date` text,
  `create_time` text,
  `status` text,
  `luggage` text,
  `intl` text,
  `customs` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=2266 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `role`
--

DROP TABLE IF EXISTS `role`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `role` (
  `id` int(11) NOT NULL auto_increment,
  `role` text,
  `fullname` text,
  `descr` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=19 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `school`
--

DROP TABLE IF EXISTS `school`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `school` (
  `id` int(11) NOT NULL auto_increment,
  `name` text,
  `mmi` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=6 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `spons_hist`
--

DROP TABLE IF EXISTS `spons_hist`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `spons_hist` (
  `id` int(11) NOT NULL auto_increment,
  `member_id` int(11) default NULL,
  `date_payment` text,
  `amount` int(11) default NULL,
  `general` text,
  `user_id` int(11) default NULL,
  `the_date` text,
  `time` text,
  `valid_from` text,
  `valid_to` text,
  `type` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=1447 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `string`
--

DROP TABLE IF EXISTS `string`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `string` (
  `the_key` text,
  `value` text
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `summary`
--

DROP TABLE IF EXISTS `summary`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `summary` (
  `id` int(11) NOT NULL auto_increment,
  `date_updated` text,
  `time_updated` text,
  `who_updated` int(11) default NULL,
  `gate_code` text,
  `registration_location` text,
  `signage` text,
  `orientation` text,
  `wind_up` text,
  `alongside` text,
  `back_to_back` text,
  `leader_name` text,
  `staff_arrival` text,
  `staff_departure` text,
  `leader_housing` text,
  `food_service` text,
  `flowers` text,
  `miscellaneous` text,
  `feedback` text,
  `field_staff_setup` text,
  `sound_setup` text,
  `check_list` text,
  `converted_spaces` text,
  `prog_person` text,
  `needs_verification` text,
  `workshop_schedule` text,
  `workshop_description` text,
  `field_staff_std_setup` text,
  `date_sent` text,
  `time_sent` text,
  `who_sent` int(11) default '0',
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=3650 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user`
--

DROP TABLE IF EXISTS `user`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user` (
  `id` int(11) NOT NULL auto_increment,
  `username` text,
  `password` text,
  `email` text,
  `first` text,
  `last` text,
  `bg` text,
  `fg` text,
  `link` text,
  `office` text,
  `cell` text,
  `txt_msg_email` text,
  `hide_mmi` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=317 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_role`
--

DROP TABLE IF EXISTS `user_role`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_role` (
  `user_id` int(11) NOT NULL default '0',
  `role_id` int(11) NOT NULL default '0',
  PRIMARY KEY  (`user_id`,`role_id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `xaccount`
--

DROP TABLE IF EXISTS `xaccount`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `xaccount` (
  `id` int(11) NOT NULL auto_increment,
  `descr` text,
  `glnum` text,
  `sponsor` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=283 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `xaccount_payment`
--

DROP TABLE IF EXISTS `xaccount_payment`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `xaccount_payment` (
  `id` int(11) NOT NULL auto_increment,
  `xaccount_id` int(11) default NULL,
  `person_id` int(11) default NULL,
  `what` text,
  `amount` decimal(8,2) default NULL,
  `type` text,
  `user_id` int(11) default NULL,
  `the_date` text,
  `time` text,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=7063 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2017-12-21  9:19:51
