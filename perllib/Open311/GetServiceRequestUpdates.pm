package Open311::GetServiceRequestUpdates;

use Moose;
use Open311;
use FixMyStreet::App;
use HTML::Entities;
use DateTime::Format::W3CDTF;

has system_user => ( is => 'rw' );
has start_date => ( is => 'ro', default => undef );
has end_date => ( is => 'ro', default => undef );
has last_update_council => ( is => 'ro', default => undef );
has suppress_alerts => ( is => 'rw', default => 0 );
has verbose => ( is => 'ro', default => 0 );

Readonly::Scalar my $AREA_ID_BROMLEY     => 2482;
Readonly::Scalar my $AREA_ID_OXFORDSHIRE => 2237;

sub fetch {
    my $self = shift;
    my $bodies = FixMyStreet::App->model('DB::Body')->search(
        {
            send_method     => 'Open311',
            comment_user_id => { '!=', undef },
            endpoint        => { '!=', '' },
        }
    );

    while ( my $body = $bodies->next ) {

        my $o = Open311->new(
            endpoint     => $body->endpoint,
            #api_key      => $body->api_key,
            #jurisdiction => $body->jurisdiction,
        );

        # custom endpoint URLs because these councils have non-standard paths
        if ( $body->areas->{$AREA_ID_BROMLEY} ) {
            my $endpoints = $o->endpoints;
            $endpoints->{update} = 'update.xml';
            $endpoints->{service_request_updates} = 'update.xml';
            $o->endpoints( $endpoints );
        } elsif ( $body->areas->{$AREA_ID_OXFORDSHIRE} ) {
            my $endpoints = $o->endpoints;
            $endpoints->{service_request_updates} = 'open311_service_request_update.cgi';
            $o->endpoints( $endpoints );
        }

        $self->suppress_alerts( $body->suppress_alerts );
        $self->system_user( $body->comment_user );
        $self->update_comments( $o, { areas => $body->areas }, );
    }
}

sub update_comments {
    my ( $self, $open311, $body_details ) = @_;

    my @args = ();
    if ( $self->start_date || $self->end_date ) {
        return 0 unless $self->start_date && $self->end_date;

        push @args, $self->start_date;
        push @args, $self->end_date;
    # default to asking for last 2 hours worth if not Bromley
    } elsif ( ! $body_details->{areas}->{$AREA_ID_BROMLEY} ) {
        my $end_dt = DateTime->now();
        my $start_dt = $end_dt->clone;
        $start_dt->add( hours => -2 );

        push @args, DateTime::Format::W3CDTF->format_datetime( $start_dt );
        push @args, DateTime::Format::W3CDTF->format_datetime( $end_dt );
    }

    my $requests = $open311->get_service_request_updates( @args );

    unless ( $open311->success ) {
        warn "Failed to fetch ServiceRequest Updates for " . join(",", keys %{$body_details->{areas}}) . ":\n" . $open311->error
            if $self->verbose;
        return 0;
    }

    for my $request (@$requests) {
        my $request_id = $request->{service_request_id};

        # If there's no request id then we can't work out
        # what problem it belongs to so just skip
        next unless $request_id;

        my $problem;
        $problem = FixMyStreet::App->model('DB::Problem')->search( {external_id => $request_id} );
        if (my $p = $problem->first) {
            my $c = $p->comments->search( { external_id => $request->{update_id} } );

            if ( !$c->first ) {
                my $comment_time = DateTime::Format::W3CDTF->parse_datetime( $request->{updated_datetime} );

                my $comment = FixMyStreet::App->model('DB::Comment')->new(
                    {
                        problem => $p,
                        user => $self->system_user,
                        external_id => $request->{update_id},
                        text => $request->{description},
                        mark_fixed => 0,
                        mark_open => 0,
                        anonymous => 0,
                        name => $self->system_user->name,
                        confirmed => $comment_time,
                        created => $comment_time,
                        state => 'confirmed',
                    }
                );
                # if the comment is older than the last update
                # do not change the status of the problem as it's
                # tricky to determine the right thing to do.
                if ( $comment->created > $p->lastupdate ) {
                    my $state = $self->map_state( $request->{status} );
                    print $request->{status};
                    print $state;
                    # don't update state unless it's an allowed state and it's
                    # actually changing the state of the problem
                    if ( FixMyStreet::DB::Result::Problem->council_states()->{$state} && $p->state ne $state &&
                        !( $p->is_fixed && FixMyStreet::DB::Result::Problem->fixed_states()->{$state} ) ) {
                        $p->state($state);
                        $comment->problem_state($state);
                    }
                }

                $p->lastupdate( $comment->created );
                $p->update;
                $comment->insert();

                if ( $self->suppress_alerts ) {
                    my $alert = FixMyStreet::App->model('DB::Alert')->find( {
                        alert_type => 'new_updates',
                        parameter  => $p->id,
                        confirmed  => 1,
                        user_id    => $p->user->id,
                    } );

                    my $alerts_sent = FixMyStreet::App->model('DB::AlertSent')->find_or_create( {
                        alert_id  => $alert->id,
                        parameter => $comment->id,
                    } );
                }
            }
        }
    }

    return 1;
}

sub fetch_details {
  use Data::Dumper;
  my $self = shift;
  my @id_list = shift;

  my %where;
  $where{id} = { 'in', @id_list };
  #Get problems
  my @problems = FixMyStreet::App->model('DB::Problem')->search( \%where );
  foreach my $problem (@problems){
    print "\n A DETAILS PROBLEM: ".$problem->id;
    #Check problem state is not  '%fixed%', 'hidden', 'closed', 'unable to fix'
    my $body = ( values %{$problem->bodies} )[0];
    my $o = Open311->new(
        endpoint     => $body->endpoint,
    );
    my $prequest = $o->get_service_custom_meta_info( $problem->external_id );
    if ( ref $prequest eq 'HASH' && exists $prequest->{request} ){
      #populate update fields ? cobrand!
      my $options;
      $options->{postcode} = $prequest->{request}{address} if $problem->postcode ne $prequest->{request}{address};
      $options->{state} = $self->map_state( lc($prequest->{request}{status}) ) if $problem->state ne $self->map_state( lc($prequest->{request}{status}) );
      $options->{category} = decode_entities($prequest->{request}{service_name}) if $problem->category ne decode_entities($prequest->{request}{service_name});
      $options->{cobrand_data} = $prequest->{request}{city_council} if $problem->cobrand_data ne $prequest->{request}{city_council};
      $options->{subcategory} = $prequest->{request}{service_area} if $problem->subcategory ne $prequest->{request}{service_area};
      #If there are changes replicate
      if ( $options ){
        print "\n A UPDATE PROBLEM \n";
        $problem->update($options);
      }
      my @tasks = values $prequest->{request}{request_completed_tasks};
      push @tasks, values $prequest->{request}{request_pending_tasks};
      $problem->update_tasks(@tasks);
    }
  }
}

sub map_state {
    my $self           = shift;
    my $incoming_state = shift;

    $incoming_state = lc($incoming_state);
    $incoming_state =~ s/_/ /g;

    my %state_map = (
        'fixed'                       => 'fixed - council',
        'not councils responsibility' => 'not responsible',
        'no further action'           => 'unable to fix',
        'open'                        => 'confirmed',
        'closed'                      => 'fixed - council',
        'ingresado'                   => 'in progress',
        'anulado'                     => 'unable to fix',
        'en proceso'                  => 'in progress',
        'finalizado'                  => 'fixed - council',
        'cerrado'                      => 'unable to fix',
    );

    return $state_map{$incoming_state} || $incoming_state;
}

1;
