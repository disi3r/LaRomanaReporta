use utf8;
package FixMyStreet::DB::Result::ContactsGroup;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->load_components("FilterColumn", "InflateColumn::DateTime", "EncodedColumn");
__PACKAGE__->table("contacts_group");
__PACKAGE__->add_columns(
  "group_id",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "contacts_group_group_id_seq",
  },
  "group_name",
  { data_type => "text", is_nullable => 0 },
  "group_color",
  { data_type => "text", is_nullable => 1 },
  "group_icon",
  { data_type => "text", is_nullable => 1 },
  "external_id",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("group_id");

__PACKAGE__->has_many('contacts', 'FixMyStreet::DB::Result::Contact', 'group_id');

# Created by DBIx::Class::Schema::Loader v0.07035 @ 2014-06-04 21:17:14
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Itaky009cU6P02qmXlE2Sg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
