use utf8;
package FixMyStreet::DB::Result::BodyDeadlines;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->load_components("FilterColumn", "InflateColumn::DateTime", "EncodedColumn");
__PACKAGE__->table("bodies_deadlines");
__PACKAGE__->add_columns(
  "group_id",
  { data_type => "integer", is_nullable => 0 },
  "body_id",
  { data_type => "text", is_nullable => 0 },
  "deadline",
  { data_type => "text", is_nullable => 0 },
  "max_hours",
  { data_type => "text", is_nullable => 0 },
  "action",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->add_unique_constraint("body_group_deadline", ["body_id", "group_id", "deadline"]);
__PACKAGE__->belongs_to(
  "body",
  "FixMyStreet::DB::Result::Body",
  { id => "body_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);
__PACKAGE__->belongs_to(
  "contacts_group",
  "FixMyStreet::DB::Result::ContactsGroup",
  { id => "group_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);
1;
