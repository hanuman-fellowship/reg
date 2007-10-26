-- DROP TABLE persons;

-- DROP TABLE kids;

-- DROP TABLE center_status;

-- DROP TABLE credit_codes;

-- DROP TABLE affiliations;

-- DROP TABLE person_affiliations;

CREATE TABLE persons (
            id                  INTEGER PRIMARY KEY,
            first_name          TEXT,
            last_name           TEXT,
            alias               TEXT,
            address             TEXT,
            city                TEXT,
            state               TEXT,
            zip                 TEXT,
            country             TEXT,
            day_phone           TEXT,
            evening_phone       TEXT,
            email               TEXT,
            fax                 TEXT,
            name_preference     INTEGER,
            sex                 TEXT,
            partner_id          INTEGER,
            akey                TEXT,
            referral            TEXT,
            ad_source           TEXT,
            wstudy              TEXT,
            ceu_requested       TEXT,
            ceu_license         TEXT,
            center_status       TEXT,
            credit_code         INTEGER, 
            birth_dt            TEXT,
            hf_dt               TEXT,
            path_dt             TEXT,
            lm_dt               TEXT,
            create_dt           TEXT,
            update_dt           TEXT
    );

CREATE TABLE kids (
            parent_id           INTEGER,
            birth_dt            TEXT,
            sex                 TEXT
    );

CREATE TABLE center_status (
            id                  INTEGER PRIMARY KEY,
            description         TEXT
    );

CREATE TABLE name_preferences (
            id                  INTEGER PRIMARY KEY,
            description         TEXT
    );

CREATE TABLE credit_codes (
            id                  INTEGER PRIMARY KEY,
            description         TEXT
    );

CREATE TABLE person_affiliation (
            person_id           INTEGER,
            affiliation_id      INTEGER,
            affilation_dt       TEXT
    );

CREATE TABLE affiliations (
            id                  INTEGER PRIMARY KEY,
            description         TEXT,
            create_dt           TEXT,
            update_dt           TEXT
    );

--
-- Load initial data
--

INSERT INTO center_status VALUES (1, "Sponsor");
INSERT INTO center_status VALUES (2, "Life Member");


INSERT INTO name_preferences VALUES (1, "Last");
INSERT INTO name_preferences VALUES (2, "First");
INSERT INTO name_preferences VALUES (3, "Last First");
INSERT INTO name_preferences VALUES (4, "First Last");
INSERT INTO name_preferences VALUES (5, "Alias First Last");
INSERT INTO name_preferences VALUES (6, "Alias Last First");
INSERT INTO name_preferences VALUES (7, "Last Alias First");
INSERT INTO name_preferences VALUES (8, "First Alias Last");
INSERT INTO name_preferences VALUES (9, "First Last Alias");
INSERT INTO name_preferences VALUES (10, "Last First Alias");


INSERT INTO credit_codes VALUES (1, "Non-existent");
INSERT INTO credit_codes VALUES (2, "Very Poor");
INSERT INTO credit_codes VALUES (3, "Poor");
INSERT INTO credit_codes VALUES (4, "Fair");
INSERT INTO credit_codes VALUES (5, "Good");
INSERT INTO credit_codes VALUES (6, "Very Good");
INSERT INTO credit_codes VALUES (7, "Excellent");
