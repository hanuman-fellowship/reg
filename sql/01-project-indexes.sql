create index program_name_idx on program (name(255));
create index program_school_id_idx on program (school_id);
create index program_summary_id_idx on program (summary_id);
create index program_sdate_idx on program(sdate(8) DESC);

create index school_name_idx on school(name(255));
create index registration_program_id_idx on registration (program_id);
create index registration_person_id_idx on registration (person_id);

