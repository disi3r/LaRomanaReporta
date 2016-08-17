package Open311::GetServiceRequestNew;

use Moose;
use Open311;
use FixMyStreet::App;
use DateTime::Format::W3CDTF;
use Data::Dumper;
use Try::Tiny;
use HTML::Entities;
use utf8;
use List::Util 'max';

has system_user => ( is => 'rw' );
has start_date => ( is => 'ro', default => undef );
has end_date => ( is => 'ro', default => undef );
has suppress_alerts => ( is => 'rw', default => 0 );
has verbose => ( is => 'ro', default => 0 );

sub fetch {
    my $self = shift;
    print 'Arranca FETCH';
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

        $self->suppress_alerts( $body->suppress_alerts );
        $self->system_user( $body->comment_user );
        $self->get_problems( $o, { areas => $body->areas }, );
    }
}

sub get_problems {
    my ( $self, $open311, $body_details ) = @_;

    my @args = ();
    if ( $self->start_date || $self->end_date ) {
        return 0 unless $self->start_date && $self->end_date;

        push @args, $self->start_date;
        push @args, $self->end_date;
    # default to asking for last 2 hours worth if not Bromley
    }
    else {
        my $end_dt = DateTime->now();
        my $start_dt = $end_dt->clone;
        $start_dt->add( hours => -2 );

        push @args, DateTime::Format::W3CDTF->format_datetime( $start_dt );
        push @args, DateTime::Format::W3CDTF->format_datetime( $end_dt );
    }

    my $requests = $open311->get_service_problems( @args );

    unless ( $open311->success ) {
        warn "Failed to fetch ServiceRequest New for " . join(",", keys %{$body_details->{areas}}) . ":\n" . $open311->error
            if $self->verbose;
        return 0;
    }

    if (@$requests){
        for my $request (@$requests) {
            my $request_id = $request->{service_request_id};
            # If there's no request id then we can't work out
            # what problem it belongs to so just skip
            next unless $request_id;
            #Check that problem has not been submitted yet
            my $report = FixMyStreet::App->model('DB::Problem')->find( {external_id => $request_id} ) || 0;
            my @tasks;
            if (!$report){
              print "\nCreate Report\n";
                #create the report
                my $prequest = $open311->get_service_custom_meta_info($request_id);
                if ( ref $prequest eq 'HASH' && exists $prequest->{request} ){
                    my $report = $self->load_data($prequest->{request}, $request_id);
                    if ($report){
                        # save the report;
                        $report->insert();
                        @tasks = values $prequest->{request}{request_completed_tasks};
                        push @tasks, values $prequest->{request}{request_pending_tasks};
                        print "\nRequest Tasks: ".Dumper(@tasks)."\n";
                        $report->update_tasks(@tasks);
                    }
                    else{
                        print 'DATA NOT FOUND';
                    }
                }
            }
            else {
              my $prequest = $open311->get_service_custom_meta_info($request_id);
              if ( ref $prequest eq 'HASH' && exists $prequest->{request} ){
                @tasks = values $prequest->{request}{request_completed_tasks};
                push @tasks, values $prequest->{request}{request_pending_tasks};
                print "\nRequest Update Tasks: ".Dumper(@tasks)."\n";
                $report->update_tasks(@tasks);
              }
            }
        }
    }
    return 1;
}

sub load_data {
    my ( $self, $prequest, $request_id ) = @_;

    my $description = '';
    my $lastupdate;

    print Dumper($prequest);
    #CHECK VALUES, mandatory: service_name, requested_datetime
    #Check for mandatory items
    if ( $prequest->{requested_datetime} && $prequest->{lat} && $prequest->{long} && $prequest->{service_name} && $prequest->{status}){
        if ( $prequest->{description} && ref \$prequest->{description} eq 'SCALAR'){
            $description = decode_entities($prequest->{description}).' ';
        }
        if ( $prequest->{address_spec} && ref \$prequest->{address_spec} eq 'SCALAR'){
            $description .= decode_entities($prequest->{address_spec});
        }
        if ( $prequest->{updated_datetime} && ref \$prequest->{updated_datetime} eq 'SCALAR'){
            $lastupdate = $prequest->{updated_datetime};
        }
        else{
            $lastupdate = $prequest->{requested_datetime};
        }
        print "\nDESCRIPTION: ".Dumper(\$description)."\n";
        my $problem = FixMyStreet::App->model('DB::Problem')->new(
            {
                user_id   => $self->system_user->id,
                bodies_str => '1',
                postcode  => $prequest->{address},
                latitude  => $prequest->{lat},
                longitude => $prequest->{long},
                title     => decode_entities($prequest->{service_name}),
                detail    => $description,
                name      => $self->system_user->name,
                service   => 'SUR',
                state     =>  $self->map_state( lc($prequest->{status}) ),
                used_map  => 1,
                anonymous => 0,
                category  => decode_entities($prequest->{service_name}) || 'Levante basurales',
                areas     => '',
                cobrand   => 'pormibarrio',
                lang      => 'es',
                lastupdate => $lastupdate,
                lastupdate_council => $lastupdate,
                confirmed => $prequest->{requested_datetime},
                external_id => $request_id,
                cobrand_data => $prequest->{city_council},
                subcategory => $prequest->{service_area},
            }
        );

        return $problem;
    }
    return 0;
}

sub map_state {
    my $self = shift;
    my $incoming_state = shift;

    $incoming_state = lc($incoming_state);
    $incoming_state =~ s/_/ /g;

    my %state_map = (
        'fixed'                       => 'fixed - council',
        'not councils responsibility' => 'not responsible',
        'no further action'           => 'unable to fix',
        'open'                        => 'confirmed',
        'cerrado'                     => 'fixed - council',
        'ingresado'                   => 'in progress',
        'anulado'                     => 'unable to fix',
        'en proceso'                  => 'in progress',
        'iniciado'                  => 'in progress',
        'finalizado'                  => 'fixed - council',
    );

    return $state_map{$incoming_state} || $incoming_state;
}

1;
