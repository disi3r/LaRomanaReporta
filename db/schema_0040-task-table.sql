create table task (
	task_id integer not null primary key,
	problem_id integer not null references problem(id), 
	created timestamp not null default ms_current_timestamp(), 
	name text not null, 
	area text, 
	status text not null default 'iniciated', 
	report text,
	planned timestamp
);
create index task_problem_id on task(problem_id);
