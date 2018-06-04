package FixMyStreet::Cobrand::PorMiBarrioEC;
use base 'FixMyStreet::Cobrand::PorMiBarrio';

use strict;
use warnings;
use FixMyStreet;
use Data::Dumper;

sub validate_document {0}
sub language_override { 'es' }
sub report_check_for_errors {return ();}

sub path_to_web_templates {
  my $self = shift;
  return [
    FixMyStreet->path_to( 'templates/web', $self->moniker )->stringify,
    FixMyStreet->path_to( 'templates/web/pormibarrio' )->stringify
  ];
}

sub disambiguate_location {
  my $self    = shift;
  my $string  = shift;
  return {
    state => 'Pichincha',
    city   => "Quito",
		country => 'EC',
  };
}

sub send_twit {1}

1;
