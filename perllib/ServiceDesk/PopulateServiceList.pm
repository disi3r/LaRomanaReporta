package ServiceDesk::PopulateServiceList;

use Moose;
use LWP::Simple;
use XML::Simple;
use FixMyStreet::App;
use ServiceDesk;
use Data::Dumper;

has bodies => ( is => 'ro' );
has found_contacts => ( is => 'rw', default => sub { [] } );
has verbose => ( is => 'ro', default => 0 );

has _current_body => ( is => 'rw' );
has _current_sd => ( is => 'rw' );
has _current_service => ( is => 'rw' );
has _group_id => ( is => 'rw' );
has _group_name => ( is => 'rw' );
has _group_external_id => ( is => 'rw' );

my $bodies = FixMyStreet::App->model('DB::Body');

sub process_bodies {
    my $self = shift;

    while ( my $body = $self->bodies->next ) {
      print "Entra BODY:".$body->send_method;
      next unless $body->endpoint;
      next unless lc($body->send_method) eq 'servicedesk';
      $self->_current_body( $body );
      $self->process_body;
    }
}

sub process_body {
  my $self = shift;
  print "Entra a PROCESS BODY";
  my $sd = ServiceDesk->new( endpoint => $self->_current_body->endpoint );
  $self->_current_sd( $sd );

  my $list = $sd->get_group_list;
  unless ( $list ) {
      my $id = $self->_current_body->id;
      my $mapit_url = mySociety::Config::get('MAPIT_URL');
      my $areas = join( ",", keys %{$self->_current_body->areas} );
      warn "Body $id for areas $areas - $mapit_url/areas/$areas.html - did not return a service list\n"
          if $self->verbose >= 1;
      return;
  }
  $list = [ $list ] unless ref $list eq 'ARRAY';
  $self->found_contacts( [] );
  foreach my $group ( @$list ) {
    #my %group_parameters = map {$_ => $group->{parameter}->{$_}->{value}} keys $group->{parameter};
    if ( $group->{parameter}->{name}->{value} && $group->{parameter}->{id}->{value} &&  $group->{parameter}->{isdeleted}->{value} ne 0) {
      print "\nGROUP LAST NAME: ".$group->{parameter}->{name}->{value};
      $self->_group_name($group->{parameter}->{name}->{value});
      $self->_group_external_id(  $group->{parameter}->{id}->{value});
      $self->_create_group;
      print "\nVUELVE DE VCREATE GROUP: ".$self->_group_id;
      if ($self->_group_id){
        print "\nVA A SERVICE LIST: ".$self->_group_external_id;
        my $services = $sd->get_service_list($self->_group_external_id);
        $self->process_services( $services );
      }
    }
    else {
      print "\n GROUP IS DELETED or incomplete: ".$group->{parameter}->{id}->{value};
    }
  }
  $self->_delete_contacts_not_in_service_list;
}

sub process_services {
  my $self = shift;
  my $list = shift;

  my $services = $list;
  # XML might only have one result and then squashed the 'array'-ness
  $services = [ $services ] unless ref $services eq 'ARRAY';
  foreach my $service ( @$services ) {
    if ( $service->{parameter}->{name}->{value} && $service->{parameter}->{id}->{value} && $service->{parameter}->{isdeleted}->{value} ne 0 ) {
      $self->_current_service( $service->{parameter} );
      $self->process_service;
    }
    else {
      print "\n CONTACT IS DELETED or incomplete: ".$service->{parameter}->{id}->{value};
    }
  }
}

sub process_service {
    my $self = shift;

    my $category = $self->_current_service->{name}->{value};

    print $self->_current_service->{id}->{value} . ': ' . $category .  "\n" if $self->verbose >= 2;
    my $contacts = FixMyStreet::App->model( 'DB::Contact')->search(
        {
            body_id => $self->_current_body->id,
            -OR => [
                email => $self->_current_service->{id}->{value},
                category => $category,
            ]
        }
    );

    if ( $contacts->count() > 1 ) {
        printf(
            "Multiple contacts for service code %s, category %s - Skipping\n",
            $self->_current_service->{id}->{value},
            $category,
        );

        # best to not mark them as deleted as we don't know what we're doing
        while ( my $contact = $contacts->next ) {
            push @{ $self->found_contacts }, $contact->email;
        }

        return;
    }

    my $contact = $contacts->first;

    if ( $contact ) {
        $self->_handle_existing_contact( $contact );
    } else {
        $self->_create_contact;
    }
}

sub _create_group {
	my ( $self ) = @_;

	if ( defined($self->_group_name) ) {
		print 'Discovered group '.$self->_group_name.'. Status:';

		my $group = FixMyStreet::App->model( 'DB::ContactsGroup')->find(
			{ group_name => $self->_group_name });

		if ( $group ) {
			print ' [FOUND ID: '.$group->group_id.']';
			$self->_group_id($group->group_id);
      $self->_group_external_id($group->external_id);
		} else {
			print ' [NOT FOUND]';

			$group = FixMyStreet::App->model( 'DB::ContactsGroup')->create({
        group_name => $self->_group_name,
        external_id => $self->_group_external_id,
      });

			print ' [CREATED ID: '.$group->group_id.']';
			$self->_group_id($group->group_id);
		}
		print "\n";
	} else {
		$self->_group_id(undef);
    $self->_group_external_id(undef);
	}
}

sub _handle_existing_contact {
  my ( $self, $contact ) = @_;

  my $service_name = $self->_normalize_service_name;

  print $self->_current_body->id . " already has a contact for service code " . $self->_current_service->{id}->{value} . "\n" if $self->verbose >= 2;

	my $group_changed = 0;
	if ( defined($contact->group_id) != defined($self->_group_id) ) {
		$group_changed = 1;
	} elsif ( defined($contact->group_id) && defined($self->_group_id) ) {
		if ( $contact->group_id != $self->_group_id ) {
			$group_changed = 1;
		}
	}

  if ( $contact->deleted || $service_name ne $contact->category || $self->_current_service->{id}->{value} ne $contact->email || $group_changed ) {
      eval {
          $contact->update(
              {
                  category => $service_name,
                  email => $self->_current_service->{id}->{value},
                  confirmed => 1,
                  deleted => 0,
                  editor => $0,
                  whenedited => \'ms_current_timestamp()',
                  note => 'automatically undeleted by script',
                  group_id => $self->_group_id,
              }
          );
      };

      if ( $@ ) {
          warn "Failed to update contact for service code " . $self->_current_service->{id}->{value} . " for body @{[$self->_current_body->id]}: $@\n"
              if $self->verbose >= 1;
          return;
      }
  }
    push @{ $self->found_contacts }, $self->_current_service->{id}->{value};
}

sub _create_contact {
    my $self = shift;

    my $service_name = $self->_normalize_service_name;

    my $contact;
    eval {
        $contact = FixMyStreet::App->model( 'DB::Contact')->create(
            {
                email => $self->_current_service->{id}->{value},
                body_id => $self->_current_body->id,
                category => $service_name,
                confirmed => 1,
                deleted => 0,
                editor => $0,
                whenedited => \'ms_current_timestamp()',
                note => 'created automatically by script',
                group_id => $self->_group_id,
            }
        );
    };

    if ( $@ ) {
        warn "Failed to create contact for service code " . $self->_current_service->{id}->{value} . " for body @{[$self->_current_body->id]}: $@\n"
            if $self->verbose >= 1;
        return;
    }
    if ( $contact ) {
        push @{ $self->found_contacts }, $self->_current_service->{id}->{value};
        print "created contact for service code " . $self->_current_service->{id}->{value} . " for body @{[$self->_current_body->id]}\n" if $self->verbose >= 2;
    }
}

sub _add_meta_to_contact {
    my ( $self, $contact ) = @_;

    print "Fetching meta data for $self->_current_service->{id}->{value}\n" if $self->verbose >= 2;
    my $meta_data = $self->_current_sd->get_service_meta_info( $self->_current_service->{id}->{value} );

    if ( ref $meta_data->{ attributes }->{ attribute } eq 'HASH' ) {
        $meta_data->{ attributes }->{ attribute } = [
            $meta_data->{ attributes }->{ attribute }
        ];
    }

    if ( ! $meta_data->{attributes}->{attribute} ) {
        warn sprintf( "Empty meta data for %s at %s",
                      $self->_current_service->{id}->{value},
                      $self->_current_body->endpoint )
        if $self->verbose;
        return;
    }

    # turn the data into something a bit more friendly to use
    my @meta =
        # remove trailing colon as we add this when we display so we don't want 2
        map { $_->{description} =~ s/:\s*//; $_ }
        # there is a display order and we only want to sort once
        sort { $a->{order} <=> $b->{order} }
        @{ $meta_data->{attributes}->{attribute} };

    if ( @meta ) {
        $contact->extra( \@meta );
    } else {
        $contact->extra( undef );
    }
    $contact->update;
}

sub _normalize_service_name {
    my $self = shift;

    # FIXME - at the moment it makes more sense to use the description
    # for cambridgeshire but need a more flexible way to set this
    my $service_name = $self->_current_service->{name}->{value};
    # remove trailing whitespace as it upsets db queries
    # to look up contact details when creating problem
    $service_name =~ s/\s+$//;

    return $service_name;
}

sub _delete_contacts_not_in_service_list {
    my $self = shift;

    print "\n NOT DELETE CONTACTS:\n".Dumper($self->found_contacts);
    my $found_contacts = FixMyStreet::App->model( 'DB::Contact')->search(
        {
            email => { -not_in => $self->found_contacts },
            body_id => $self->_current_body->id,
            deleted => 0,
        }
    );

    $found_contacts->update(
        {
            deleted => 1,
            editor  => $0,
            whenedited => \'ms_current_timestamp()',
            note => 'automatically marked as deleted by script'
        }
    );
}

1;
