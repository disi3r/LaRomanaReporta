use utf8;
package FixMyStreet::DB::Result::Task;

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->load_components("FilterColumn", "InflateColumn::DateTime", "EncodedColumn");
__PACKAGE__->table("task");
__PACKAGE__->add_columns(
  "task_id",
  { data_type => "integer", is_nullable => 0 },
  "problem_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "created",
  {
    data_type     => "timestamp",
    default_value => \"ms_current_timestamp()",
    is_nullable   => 0,
  },
  "name",
  { data_type => "text", , is_nullable => 0 },
  "area",
  { data_type => "text", is_nullable => 1 },
  "status",
  { data_type => "text", is_nullable => 1 },
  "report",
  { data_type => "text", is_nullable => 1 },
  "planned",
  { data_type     => "timestamp", is_nullable => 1 }
);

__PACKAGE__->set_primary_key("task_id");

__PACKAGE__->belongs_to(
  "problem_id",
  "FixMyStreet::DB::Result::Problem",
  { ref => "id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

