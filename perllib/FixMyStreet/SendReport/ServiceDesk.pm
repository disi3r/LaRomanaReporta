package FixMyStreet::SendReport::ServiceDesk;

use Moose;
use namespace::autoclean;

BEGIN { extends 'FixMyStreet::SendReport'; }

use FixMyStreet::App;
use mySociety::Config;
use DateTime::Format::W3CDTF;
use ServiceDesk;
use Readonly;
use Data::Dumper;
use warnings;

sub send {
    my $self = shift;
    my ( $row, $h ) = @_;

    my $result = -1;
    print Dumper($h);
    print 'Internal ID: '.$row->id."\n";
    foreach my $body ( @{ $self->bodies } ) {
        my $conf = $self->body_config->{ $body->id };

        my $always_send_latlong = 1;
        my $send_notpinpointed  = 0;
        my $use_service_as_deviceid = 0;

        my $extended_desc = 1;

        # To rollback temporary changes made by this function
        my $revert = 0;

        # FIXME: we've already looked this up before
        my $contact = FixMyStreet::App->model("DB::Contact")->find( {
            deleted => 0,
            body_id => $body->id,
            category => $row->category
        } );

        my %sd_params = (
            #jurisdiction            => $conf->jurisdiction,
            endpoint                => $conf->endpoint,
            #api_key                 => $conf->api_key,
            always_send_latlong     => $always_send_latlong,
            send_notpinpointed      => $send_notpinpointed,
            use_service_as_deviceid => $use_service_as_deviceid,
            extended_description    => $extended_desc,
        );

        if ($row->cobrand eq 'pormibarrio') {
            #$row->extra( [ { 'name' => 'external_id', 'value' => $row->id  } ]  );

            my $lat=$h->{latitude};
            my $long=$h->{longitude};

            #use LWP::Simple;
            #my $url = 'http://nominatim.openstreetmap.org/reverse?format=xml&lat='.$lat.'&lon='.$long.'&zoom=18&addressdetails=1';
            #my $resp = get($url);
            #die "Couldn't get resource" unless defined $resp;
            #use XML::Simple qw(:strict);
            #my $parsed = XMLin( $resp, KeyAttr => 'addressparts', ForceArray => [], ContentKey => '-content' );
            #my @number_arr = split(',', $parsed->{addressparts}->{house_number});
            #use integer;
            #my $key = (($#number_arr+1)/2);
            #$key += (($#number_arr+1)%2);
            #$key -= 1;
            #my $number = $number_arr[$key];
            #binmode(STDOUT, ":utf8");
            #my $street = $parsed->{addressparts}->{road}.', '.$number.', '.$parsed->{addressparts}->{suburb}.', '.$parsed->{addressparts}->{postcode};
            #$row->{address_string} = $street;#closest_address
            #$revert = 1;
            print "PORMIBARRIO \n";
        }

        if (FixMyStreet->test_mode) {
            my $test_res = HTTP::Response->new();
            $test_res->code(200);
            $test_res->message('OK');
            $test_res->content('<?xml version="1.0" encoding="utf-8"?><service_requests><request><service_request_id>248</service_request_id></request></service_requests>');
            $sd_params{test_mode} = 1;
            $sd_params{test_get_returns} = { 'requests.xml' => $test_res };
        }

        my $sd = ServiceDesk->new( %sd_params );

        my $resp = $sd->send_service_request( $row, $h, $contact->email );
        print Dumper($resp);
        print 'External ID:'.Dumper($resp)."\n";

        # make sure we don't save user changes from above
        $row->discard_changes() if $revert;

        if ( $resp ) {
            $row->external_id( $resp );
            $row->send_method_used('ServiceDesk');
            $result *= 0;
            $self->success( 1 );
        } else {
            $result *= 1;
        }
    }

    $self->error( 'Failed to send over ServiceDesk' ) unless $self->success;

    return $result;
}

1;
