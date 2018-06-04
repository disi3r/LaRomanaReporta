CREATE TABLE bodies_deadlines (
  body_id INTEGER NOT NULL REFERENCES body(id),
  group_id INTEGER NOT NULL REFERENCES contacts_group(group_id),
  deadline TEXT NOT NULL,
  max_hours INTEGER NOT NULL,
  action TEXT,

  CONSTRAINT body_group_deadline PRIMARY KEY (body_id,group_id,deadline)
);
