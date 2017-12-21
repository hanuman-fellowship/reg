PRAGMA synchronous = OFF;
PRAGMA journal_mode = MEMORY;
BEGIN TRANSACTION;
CREATE TABLE `affil_people` (
  `a_id` integer default NULL
,  `p_id` integer default NULL
);
CREATE TABLE `affil_program` (
  `a_id` integer default NULL
,  `p_id` integer default NULL
);
CREATE TABLE `affil_reports` (
  `report_id` integer default NULL
,  `affiliation_id` integer default NULL
);
CREATE TABLE `affils` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `descrip` text
,  `system` text NOT NULL
,  `selectable` text NOT NULL
);
CREATE TABLE `annotation` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `cluster_type` text
,  `label` text
,  `x` integer default NULL
,  `y` integer default NULL
,  `x1` integer default NULL
,  `y1` integer default NULL
,  `x2` integer default NULL
,  `y2` integer default NULL
,  `shape` text
,  `thickness` integer default NULL
,  `color` text
,  `inactive` text
);
CREATE TABLE `block` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `house_id` integer default NULL
,  `sdate` text
,  `edate` text
,  `nbeds` integer default NULL
,  `reason` text
,  `user_id` integer default NULL
,  `the_date` text
,  `time` text
,  `comment` text
,  `allocated` text
,  `npeople` integer default NULL
,  `event_id` integer default NULL
,  `program_id` integer default NULL
,  `rental_id` integer default NULL
);
CREATE TABLE `book` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `title` text
,  `author` text
,  `publisher` text
,  `description` text
,  `location` text
,  `subject` text
,  `media` integer default NULL
);
CREATE TABLE `booking` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `meet_id` integer default NULL
,  `rental_id` integer default NULL
,  `program_id` integer default NULL
,  `event_id` integer default NULL
,  `sdate` text
,  `edate` text
,  `breakout` text
,  `dorm` text
);
CREATE TABLE `canpol` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` text
,  `policy` text
);
CREATE TABLE `category` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` text
);
CREATE TABLE `check_out` (
  `book_id` integer default NULL
,  `person_id` integer default NULL
,  `due_date` text
);
CREATE TABLE `cluster` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` text
,  `type` text
,  `cl_order` integer default '0'
);
CREATE TABLE `conf_history` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `reg_id` integer default NULL
,  `note` text
,  `user_id` integer default NULL
,  `the_date` text
,  `time` text
);
CREATE TABLE `config` (
  `house_id` integer default NULL
,  `the_date` text
,  `sex` text
,  `curmax` integer default NULL
,  `cur` integer default NULL
,  `program_id` integer default NULL
,  `rental_id` integer default NULL
);
CREATE TABLE `confnote` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `abbr` text
,  `expansion` text
);
CREATE TABLE `credit` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `person_id` integer default NULL
,  `reg_id` integer default NULL
,  `date_given` text
,  `amount` integer default NULL
,  `date_expires` text
,  `date_used` text
,  `used_reg_id` integer default NULL
);
CREATE TABLE `deposit` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `user_id` integer default NULL
,  `date_start` text
,  `date_end` text
,  `time` text
,  `cash` decimal(8,2) default NULL
,  `chk` decimal(8,2) default NULL
,  `credit` decimal(8,2) default NULL
,  `online` decimal(8,2) default NULL
,  `sponsor` text
);
CREATE TABLE `donation` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `person_id` integer default NULL
,  `project_id` integer default NULL
,  `the_date` text
,  `amount` integer default NULL
,  `type` text
,  `who_d` integer default NULL
,  `date_d` text
,  `time_d` text
);
CREATE TABLE `event` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` text
,  `descr` text
,  `sdate` text
,  `edate` text
,  `sponsor` text
,  `max` text
,  `organization_id` integer NOT NULL
,  `pr_alert` text
,  `user_id` integer NOT NULL default '0'
,  `the_date` text NOT NULL
,  `time` text NOT NULL
);
CREATE TABLE `exception` (
  `prog_id` integer default NULL
,  `tag` text
,  `value` text
);
CREATE TABLE `glossary` (
  `term` text
,  `definition` text
);
CREATE TABLE `house` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` text
,  `max` integer default NULL
,  `bath` text
,  `tent` text
,  `center` text
,  `cabin` text
,  `priority` integer default NULL
,  `x` integer default NULL
,  `y` integer default NULL
,  `cluster_id` integer default NULL
,  `cluster_order` integer default NULL
,  `inactive` text
,  `disp_code` text
,  `comment` text
,  `resident` text
,  `cat_abode` text
,  `sq_foot` text
,  `key_card` text
);
CREATE TABLE `housecost` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` text
,  `single_bath` integer default NULL
,  `single` integer default NULL
,  `dble_bath` integer default NULL
,  `dble` integer default NULL
,  `triple` integer default NULL
,  `dormitory` integer default NULL
,  `economy` integer default NULL
,  `center_tent` integer default NULL
,  `own_tent` integer default NULL
,  `own_van` integer default NULL
,  `commuting` integer default NULL
,  `type` text
,  `inactive` text
);
CREATE TABLE `issue` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `priority` text
,  `title` text
,  `notes` text
,  `date_entered` text
,  `date_closed` text
,  `user_id` integer default NULL
);
CREATE TABLE `leader` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `person_id` integer default NULL
,  `public_email` text
,  `url` text
,  `image` text
,  `biography` text
,  `assistant` text
,  `l_order` integer default NULL
,  `just_first` text
);
CREATE TABLE `leader_program` (
  `l_id` integer default NULL
,  `p_id` integer default NULL
);
CREATE TABLE `level` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` text
,  `long_term` text
,  `public` text
,  `school_id` integer default NULL
,  `name_regex` text
,  `glnum_suffix` text
);
CREATE TABLE `make_up` (
  `house_id` integer NOT NULL
,  `date_vacated` text
,  `date_needed` text
,  `refresh` text
,  PRIMARY KEY  (`house_id`)
);
CREATE TABLE `meal` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `sdate` text
,  `edate` text
,  `breakfast` integer default NULL
,  `lunch` integer default NULL
,  `dinner` integer default NULL
,  `comment` text
,  `user_id` integer default NULL
,  `the_date` text
,  `time` text
);
CREATE TABLE `meeting_place` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `abbr` text
,  `name` text
,  `max` integer default NULL
,  `disp_ord` integer default NULL
,  `color` text
,  `sleep_too` text
);
CREATE TABLE `member` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `person_id` integer default NULL
,  `category` text
,  `date_general` text
,  `date_sponsor` text
,  `sponsor_nights` integer default NULL
,  `date_life` text
,  `free_prog_taken` text
,  `total_paid` integer default NULL
,  `voter` text NOT NULL
);
CREATE TABLE `mmi_payment` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `person_id` integer default NULL
,  `amount` decimal(8,2) default NULL
,  `glnum` text
,  `the_date` text
,  `type` text
,  `deleted` text
,  `reg_id` integer default NULL
,  `note` text
);
CREATE TABLE `night_hist` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `member_id` integer default NULL
,  `num_nights` integer default NULL
,  `action` text
,  `reg_id` integer default NULL
,  `user_id` integer default NULL
,  `the_date` text
,  `time` text
);
CREATE TABLE `organization` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` varchar(30) NOT NULL
,  `on_prog_cal` varchar(3) NOT NULL default ''
,  `color` varchar(13) default '255,255,255'
);
CREATE TABLE `people` (
  `last` text
,  `first` text
,  `sanskrit` text
,  `addr1` text
,  `addr2` text
,  `city` text
,  `st_prov` text
,  `zip_post` text
,  `country` text
,  `akey` text
,  `tel_home` text
,  `tel_work` text
,  `tel_cell` text
,  `email` text
,  `sex` text
,  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `id_sps` integer default NULL
,  `date_updat` text
,  `date_entrd` text
,  `comment` text
,  `e_mailings` text NOT NULL
,  `snail_mailings` text NOT NULL
,  `share_mailings` text NOT NULL
,  `deceased` text NOT NULL
,  `inactive` text NOT NULL
,  `safety_form` text
,  `secure_code` text NOT NULL
,  `temple_id` integer default NULL
,  `waiver_signed` text
,  `only_temple` text
);
CREATE TABLE `program` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` text
,  `title` text
,  `subtitle` text
,  `glnum` text
,  `housecost_id` integer default NULL
,  `retreat` text
,  `sdate` text
,  `edate` text
,  `tuition` integer default NULL
,  `confnote` text
,  `url` text
,  `webdesc` text
,  `webready` text
,  `image` text
,  `kayakalpa` text
,  `canpol_id` integer default NULL
,  `extradays` integer default NULL
,  `full_tuition` integer default NULL
,  `deposit` integer default NULL
,  `collect_total` text
,  `linked` text
,  `unlinked_dir` text
,  `ptemplate` text
,  `cl_template` text
,  `sbath` text
,  `economy` text
,  `footnotes` text
,  `reg_start` text
,  `reg_end` text
,  `prog_start` text
,  `prog_end` text
,  `reg_count` integer default NULL
,  `lunches` text
,  `max` text
,  `notify_on_reg` text
,  `summary_id` integer default NULL
,  `rental_id` integer default NULL
,  `do_not_compute_costs` text
,  `dncc_why` text
,  `color` text
,  `single` text
,  `allow_dup_regs` text
,  `commuting` text
,  `percent_tuition` integer default NULL
,  `refresh_days` text
,  `category_id` integer default '0'
,  `facebook_event_id` text NOT NULL
,  `not_on_calendar` text
,  `tub_swim` text
,  `cancelled` text NOT NULL
,  `pr_alert` text
,  `school_id` integer default NULL
,  `level_id` integer default NULL
,  `bank_account` text
,  `waiver_needed` text
,  `housing_not_needed` text
,  `req_pay` text NOT NULL
,  `program_created` text
,  `created_by` integer default '0'
);
CREATE TABLE `program_cluster` (
  `program_id` integer default NULL
,  `cluster_id` integer default NULL
,  `seq` integer default NULL
);
CREATE TABLE `program_doc` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `program_id` integer NOT NULL
,  `title` text
,  `suffix` text
);
CREATE TABLE `project` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `descr` text
,  `glnum` text
);
CREATE TABLE `proposal` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `date_of_call` text
,  `group_name` text
,  `rental_type` text
,  `max` integer default NULL
,  `min` integer default NULL
,  `dates_requested` text
,  `checkin_time` text
,  `checkout_time` text
,  `other_things` text
,  `meeting_space` text
,  `housing_space` text
,  `leader_housing` text
,  `special_needs` text
,  `food_service` text
,  `other_requests` text
,  `program_meeting_date` text
,  `denied` text
,  `provisos` text
,  `first` text
,  `last` text
,  `addr1` text
,  `addr2` text
,  `city` text
,  `st_prov` text
,  `zip_post` text
,  `country` text
,  `tel_home` text
,  `tel_work` text
,  `tel_cell` text
,  `email` text
,  `cs_first` text
,  `cs_last` text
,  `cs_addr1` text
,  `cs_addr2` text
,  `cs_city` text
,  `cs_st_prov` text
,  `cs_zip_post` text
,  `cs_country` text
,  `cs_tel_home` text
,  `cs_tel_work` text
,  `cs_tel_cell` text
,  `cs_email` text
,  `deposit` integer default NULL
,  `misc_notes` text
,  `rental_id` integer default NULL
,  `person_id` integer default NULL
,  `cs_person_id` integer default NULL
,  `staff_ok` text
);
CREATE TABLE `reg_charge` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `reg_id` integer default NULL
,  `user_id` integer default NULL
,  `the_date` text
,  `time` text
,  `amount` decimal(8,2) default NULL
,  `what` text
,  `automatic` text
,  `type` integer default '5'
);
CREATE TABLE `reg_history` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `reg_id` integer default NULL
,  `user_id` integer default NULL
,  `the_date` text
,  `time` text
,  `what` text
);
CREATE TABLE `reg_payment` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `reg_id` integer default NULL
,  `user_id` integer default NULL
,  `the_date` text
,  `time` text
,  `amount` decimal(8,2) default NULL
,  `type` text
,  `what` text
);
CREATE TABLE `registration` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `person_id` integer default NULL
,  `program_id` integer default NULL
,  `deposit` integer default NULL
,  `referral` text
,  `adsource` text
,  `kids` text
,  `comment` text
,  `confnote` text
,  `h_type` text
,  `h_name` text
,  `carpool` text
,  `hascar` text
,  `arrived` text
,  `cancelled` text
,  `date_postmark` text
,  `time_postmark` text
,  `balance` integer default NULL
,  `date_start` text
,  `date_end` text
,  `early` text
,  `late` text
,  `ceu_license` text
,  `letter_sent` text
,  `status` text
,  `nights_taken` integer default NULL
,  `free_prog_taken` text
,  `house_id` integer default NULL
,  `cabin_room` text
,  `leader_assistant` text
,  `pref1` text
,  `pref2` text
,  `share_first` text
,  `share_last` text
,  `manual` text
,  `work_study` text
,  `work_study_comment` text
,  `rental_before` text
,  `rental_after` text
,  `work_study_safety` text
,  `transaction_id` text NOT NULL
,  `from_where` text
);
CREATE TABLE `rental` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` text
,  `title` text
,  `subtitle` text
,  `glnum` text
,  `sdate` text
,  `edate` text
,  `url` text
,  `webdesc` text
,  `linked` text
,  `phone` text
,  `email` text
,  `comment` text
,  `housecost_id` integer default NULL
,  `max` integer default NULL
,  `balance` decimal(8,2) default NULL
,  `contract_sent` text
,  `sent_by` text
,  `contract_received` text
,  `received_by` text
,  `tentative` text
,  `start_hour` text
,  `end_hour` text
,  `coordinator_id` integer default NULL
,  `cs_person_id` integer default NULL
,  `lunches` text
,  `status` text
,  `deposit` integer default NULL
,  `summary_id` integer default NULL
,  `mmc_does_reg` text
,  `program_id` integer default NULL
,  `proposal_id` integer default NULL
,  `color` text
,  `housing_note` text
,  `grid_code` text
,  `expected` integer default NULL
,  `staff_ok` text
,  `refresh_days` text
,  `rental_follows` text
,  `cancelled` text NOT NULL
,  `fixed_cost_houses` text
,  `fch_encoded` text
,  `grid_stale` text
,  `pr_alert` text
,  `arrangement_sent` text
,  `arrangement_by` text
,  `counts` text
,  `grid_max` integer default '0'
,  `housing_charge` integer default '0'
,  `rental_created` text
,  `created_by` integer default '0'
);
CREATE TABLE `rental_booking` (
  `rental_id` integer default NULL
,  `date_start` text
,  `date_end` text
,  `house_id` integer default NULL
,  `h_type` text
);
CREATE TABLE `rental_charge` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `rental_id` integer default NULL
,  `amount` decimal(8,2) default NULL
,  `what` text
,  `user_id` integer default NULL
,  `the_date` text
,  `time` text
);
CREATE TABLE `rental_cluster` (
  `rental_id` integer default NULL
,  `cluster_id` integer default NULL
);
CREATE TABLE `rental_payment` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `rental_id` integer default NULL
,  `amount` decimal(8,2) default NULL
,  `type` text
,  `user_id` integer default NULL
,  `the_date` text
,  `time` text
);
CREATE TABLE `reports` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `descrip` text
,  `rep_order` text
,  `zip_range` text
,  `format` integer default NULL
,  `nrecs` integer default NULL
,  `last_run` text
,  `update_cutoff` text NOT NULL
,  `end_update_cutoff` text NOT NULL
);
CREATE TABLE `req_payment` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `org` text
,  `person_id` integer default '0'
,  `amount` integer default '0'
,  `for_what` integer default '0'
,  `the_date` text
,  `reg_id` integer default '0'
,  `note` text
,  `code` text
);
CREATE TABLE `resident` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `person_id` integer default NULL
,  `comment` text
,  `image` text
);
CREATE TABLE `resident_note` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `resident_id` integer default NULL
,  `the_date` text
,  `the_time` text
,  `note` text
);
CREATE TABLE `ride` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `rider_id` integer default NULL
,  `driver_id` integer default NULL
,  `from_to` text
,  `pickup_date` text
,  `airport` text
,  `carrier` text
,  `flight_num` text
,  `flight_time` text
,  `cost` decimal(8,2) default NULL
,  `comment` text
,  `paid_date` text
,  `sent_date` text
,  `type` text
,  `shuttle` integer default NULL
,  `pickup_time` text
,  `create_date` text
,  `create_time` text
,  `status` text
,  `luggage` text
,  `intl` text
,  `customs` text
);
CREATE TABLE `role` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `role` text
,  `fullname` text
,  `descr` text
);
CREATE TABLE `school` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` text
,  `mmi` text
);
CREATE TABLE `spons_hist` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `member_id` integer default NULL
,  `date_payment` text
,  `amount` integer default NULL
,  `general` text
,  `user_id` integer default NULL
,  `the_date` text
,  `time` text
,  `valid_from` text
,  `valid_to` text
,  `type` text
);
CREATE TABLE `string` (
  `the_key` text
,  `value` text
);
CREATE TABLE `summary` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `date_updated` text
,  `time_updated` text
,  `who_updated` integer default NULL
,  `gate_code` text
,  `registration_location` text
,  `signage` text
,  `orientation` text
,  `wind_up` text
,  `alongside` text
,  `back_to_back` text
,  `leader_name` text
,  `staff_arrival` text
,  `staff_departure` text
,  `leader_housing` text
,  `food_service` text
,  `flowers` text
,  `miscellaneous` text
,  `feedback` text
,  `field_staff_setup` text
,  `sound_setup` text
,  `check_list` text
,  `converted_spaces` text
,  `prog_person` text
,  `needs_verification` text
,  `workshop_schedule` text
,  `workshop_description` text
,  `field_staff_std_setup` text
,  `date_sent` text
,  `time_sent` text
,  `who_sent` integer default '0'
);
CREATE TABLE `user` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `username` text
,  `password` text
,  `email` text
,  `first` text
,  `last` text
,  `bg` text
,  `fg` text
,  `link` text
,  `office` text
,  `cell` text
,  `txt_msg_email` text
,  `hide_mmi` text
);
CREATE TABLE `user_role` (
  `user_id` integer NOT NULL default '0'
,  `role_id` integer NOT NULL default '0'
,  PRIMARY KEY  (`user_id`,`role_id`)
);
CREATE TABLE `xaccount` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `descr` text
,  `glnum` text
,  `sponsor` text
);
CREATE TABLE `xaccount_payment` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `xaccount_id` integer default NULL
,  `person_id` integer default NULL
,  `what` text
,  `amount` decimal(8,2) default NULL
,  `type` text
,  `user_id` integer default NULL
,  `the_date` text
,  `time` text
);
CREATE INDEX "idx_people_i_last" ON "people" (`last`);
CREATE INDEX "idx_people_i_akey" ON "people" (`akey`);
CREATE INDEX "idx_people_i_sps" ON "people" (`id_sps`);
CREATE INDEX "idx_config_i_config" ON "config" (`house_id`,`the_date`);
END TRANSACTION;
