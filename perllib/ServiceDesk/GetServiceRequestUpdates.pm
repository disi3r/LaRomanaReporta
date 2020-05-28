package ServiceDesk::GetServiceRequestUpdates;

use Moose;
use ServiceDesk;
use FixMyStreet::App;
use HTML::Entities;
use DateTime;
use DateTime::Format::W3CDTF;

has system_user => ( is => 'rw' );
has start_date => ( is => 'ro', default => undef );
has end_date => ( is => 'ro', default => undef );
has last_update_council => ( is => 'ro', default => undef );
has suppress_alerts => ( is => 'rw', default => 0 );
has verbose => ( is => 'ro', default => 0 );
has _current_sd => ( is => 'rw' );

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
        my $sd = ServiceDesk->new( endpoint => $self->_current_body->endpoint );
        $self->_current_sd( $sd );

        $self->suppress_alerts( $body->suppress_alerts );
        $self->system_user( $body->comment_user );

        #$self->update_comments( $o, { areas => $body->areas }, );
    }
}

sub update_comments {
    my ( $self, $requests ) = @_;

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
    #Check problem state is not  '%fixed%', 'hidden', 'closed', 'unable to fix'
    my $body = ( values %{$problem->bodies} )[0];
    $self->system_user( $body->comment_user );
    my $o = ServiceDesk->new(
    endpoint     => $body->endpoint,
    );
    #check state
    my $prequest = $o->get_service_requests($problem->external_id);
    #Check status
    if ( ref $prequest eq 'HASH' && exists $prequest->{parameter}->{status}->{value} ){
      #If Closed then get the clousure parameters
      my $state = '';
      my $comment = '';
      if ( $prequest->{parameter}->{status}->{value} eq "Closed" ) {
        #Canceled, Failed, Posponed, Success, Unable to reproduce
        #TODO Ver que opción va por defecto
        if ( $prequest->{parameter}->{closurecode}->{value} eq '' ) {
          $state = 'unable to fix';
        }
        else {
          $state = $self->map_state( $prequest->{parameter}->{closurecode}->{value} );
        }
        if ( $prequest->{parameter}->{closurecomments}->{value} ne '' ) {
          $comment = $prequest->{parameter}->{closurecomments}->{value}.'. ';
        }
      }
      else {
        $state = $self->map_state( $prequest->{parameter}->{status}->{value} );
      }
      if ( $state && $problem->state ne $state ) { #&& !( $problem->is_fixed && FixMyStreet::DB::Result::Problem->fixed_states()->{$state} ) ) {
        #change state with resolution
        print "\n\nGOING FOR RESOLUTION\n";
        my $resrequest = $o->get_service_resolution( $problem->external_id );
        #print Dumper($resrequest);
        #TODO: No spec for lastupdatedtime... this is what happens;
        if ($resrequest) {
          my $time_str = substr $resrequest->{lastupdatedtime}, 0, -3;
          my $res_time = DateTime->from_epoch(epoch => $time_str); #Asumed UTC;
          $res_time->set_time_zone( FixMyStreet->config('TIME_ZONE') );
          if ( !$problem->lastupdate_council || $res_time > $problem->lastupdate_council ){
            #Create comment
            $comment = $comment.$resrequest->{resolution};
            $self->_sd_create_comment($problem, $state, $comment, $res_time );
          }
        }
      }
    }
    #Check notes
    my $trequest = $o->get_service_custom_meta_info( $problem->external_id );
    $trequest = [ $trequest ] if ref $trequest ne 'ARRAY';
    foreach my $note (@{$trequest}) {
      if ( exists $note->{parameter} && $note->{parameter}->{isPublic}->{value} eq 'true' ) {
        my @note_url = split /\//, $note->{URI};
        my $note_id = $note_url[-1];
        print "\n\nNOTE ID:".$note_id."\n";
        my $c = $problem->comments->search( { external_id => $note_id } );
        if ( !$c->first ) {
          #TODO: No spec for lastupdatedtime... this is what happens;
          my $note_time_str = substr $note->{parameter}->{notesDate}->{value}, 0, -3;
          my $note_time = DateTime->from_epoch(epoch => $note_time_str);#, time_zone => FixMyStreet->config('TIME_ZONE') );
          $note_time->set_time_zone( FixMyStreet->config('TIME_ZONE') );
          my $note_comment = ref($note->{parameter}->{notesText}->{value}) eq 'HASH' ? $note->{parameter}->{notesText}->{value}->{content} : $note->{parameter}->{notesText}->{value};
          $self->_sd_create_comment($problem, undef, $note_comment, $note_time, $note_id );
        }
      }
    }
    $problem->lastcheck(\'ms_current_timestamp()');
    $problem->update;
  }
  return 1;
}

sub _sd_create_comment {
  my ( $self, $p, $state, $details, $changed, $id ) = @_;
  my $w3c = DateTime::Format::W3CDTF->new;
  my $req_time = $w3c->format_datetime( $changed );
  my $comment = FixMyStreet::App->model('DB::Comment')->new({
    problem => $p,
    user => $self->system_user,
    text => $details,
    mark_fixed => 0,
    mark_open => 0,
    anonymous => 0,
    name => $self->system_user->name,
    confirmed => $req_time,
    created => \'ms_current_timestamp()',
    state => 'confirmed',
    external_id => $id
  });
  if ( $state ) {
    $p->state($state);
    $comment->problem_state($state);
  }
  #already validated
  print "\nPROBLEM UPDATE\n";
  $p->lastupdate( $req_time ) if $p->lastupdate < $changed;
  $p->lastupdate_council( $req_time );
  $p->update;
  print "\nCOMMENT INSERT\n";
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
  return 1;
}

sub map_state {
    my $self           = shift;
    my $incoming_state = shift;

    $incoming_state = lc($incoming_state);
    $incoming_state =~ s/_/ /g;
    print "\n INCOMING: ".$incoming_state;
    my %state_map = (
        'resuelto'            => 'fixed - council',
        #'not councils responsibility' => 'not responsible',
        'cerrado'             => 'unable to fix',
        'abierto'             => 'confirmed',
        'en espera'           => 'planned',
        'posponed'            => 'planned',
        'ingresado'           => 'in progress',
        'asignado'            => 'in progress',
        'closed'              => 'unable to fix',
        'en proceso'          => 'in progress',
        'resolved'            => 'fixed - council',
        'failed'              => 'unable to fix',
        'iniciado'            => 'in progress',
        'unable to reproduce' => 'unable to fix',
    );
    print "\n OUTGOING: ".$state_map{$incoming_state};
    return $state_map{$incoming_state} || $incoming_state;
}
1;
