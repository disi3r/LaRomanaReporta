package FixMyStreet::Cobrand::PorMiBarrio;
use base 'FixMyStreet::Cobrand::Default';

use strict;
use warnings;
use JSON;
use HTTP::Request::Common;
use Data::Dumper;
use LWP::UserAgent;
use DateTime;
use Switch;
use URI;
use Scalar::Util qw(looks_like_number);
#use Params::Util qw<_HASH _HASH0 _HASHLIKE>;

sub process_extras {
	my $self = shift;
    my $c = shift;
    my $body = shift;
    my $extra = shift;

    if ($c->stash->{report}->{has_photo}){
    	my $image_url = FixMyStreet->path_to( 'web', 'photo', $c->stash->{report}->id . '.*' );
    	push @$extra, { name => 'image_url', value => $image_url };
    }
}


=head2 user_check_for_errors

Perform validation for new users. Takes Catalyst context object as an argument

=cut

sub user_check_for_errors {
    my $self = shift;
    my $c = shift;

    return (
        %{ $c->stash->{field_errors} },
        %{ $c->stash->{user}->check_for_errors },
    );
}

sub resend_in_reopen {1}

sub validate_document {1}

sub validate_identity_document {
	my $self = shift;
	my $identity_document = shift;

	#my $identity_document = $c->stash->{user}->identity_document;

	if ( $identity_document ) {
		$identity_document = Utils::trim_text( $identity_document );
		$identity_document =~ s/\.|\ //g;

		my @parts = split /-/, $identity_document;

		if (scalar @parts eq 1) {
			push @parts, chop $parts[0];
		}
		my @identity_document_array = reverse(split("", $parts[0]));
		#Validate only numbers
		if ( !looks_like_number($parts[0]) || $parts[0] < 1 || scalar @identity_document_array < 6 || scalar @identity_document_array > 7 ) {
			return 0;
		}
		#1234567-X -> X = [(1x8) + (2x1) + (3x2) + (4x3) + (5x4) + (6x7) + (7x6)] mod 10 -> X = [ 8 +2 +6 +12 +20 +42 +42] mod 10 = 132 mod 10 = 2
		my @magic = (4,3,6,7,8,9,2);
		my $result = 0;
		for ( my $pos = 0; $pos < scalar @identity_document_array; $pos++ ) {
				$result += ($magic[$pos] * $identity_document_array[$pos])%10;
		}
		my $verification;
		if( $result%10 eq 0 ){
      		$verification = 0;
    		}
    		else{
      		$verification = 10 - $result % 10;
    		}
		if ( $verification eq $parts[1] ){
			#Normalizamos la cédula a guardar
			return $parts[0].'-'.$parts[1];
		}
	}
	return 0;
}

=head2 report_check_for_errors

Perform validation for new reports. Takes Catalyst context object as an argument

=cut

sub report_check_for_errors {
    my $self = shift;
    my $c = shift;

	my $identity_document = $c->stash->{report}->user->identity_document;

    my %errors = ();

    if ( $identity_document ) {
		if ( !$self->validate_identity_document( $identity_document ) ) {
			$errors{identity_document} = _('Please enter a valid ID');
		}
	} else {
        $errors{identity_document} = _('Please enter your ID');
    }

    return (
        %{ $c->stash->{field_errors} },
        %{ $c->stash->{report}->user->check_for_errors },
        %{ $c->stash->{report}->check_for_errors },
        %errors,
    );
}

=head 2 pin_colour

Returns the colour of pin to be used for a particular report
(so perhaps different depending upon the age of the report).

=cut
sub pin_colour {
    my ( $self, $p, $context, $c, $categories ) = @_;
    #return 'green' if time() - $p->confirmed->epoch < 7 * 24 * 60 * 60;

    if ( $context eq 'around' || $context eq 'reports' || $context eq 'my') {
		my $category_name = $p->category;

		if ( $categories && $categories->{$category_name}) {
			#Get category pin
			#Get category icon
			my $icon = $p->category_icon( $categories->{$category_name} );
			if ($p->is_fixed){
				$icon .= '-resuelto';
			}
			else{
				if ($p->state eq 'in progress'){
					$icon .= '-proceso';
				}
			}
			return $icon;
		} else {
			return 'yellow';
		}
	} else {
		return $p->is_fixed ? 'green' : 'red';
	}
}

# let staff and owners hide reports
sub users_can_hide { 1 }

sub language_override { 'es' }

sub site_title { return 'PorMiBarrio'; }

sub on_map_default_max_pin_age {
    return '6 month';
}
#this is a test
sub problems_clause {
	return {-NOT =>{-AND => [
											'confirmed' => { '<', \"current_timestamp-'3 month'::interval" },
											'state' => { 'like', 'fixed%' },
									]}};
}

sub geocode_postcode {
    my ( $self, $s, $c ) = @_;
		my $response = {};
    #$response->{error} = ( { address => 'Direccion', latitude => 'latitud', longitude => 'longi' } );
    my @term_arr = split(',', $s);

    if (@term_arr){
			my $area = shift @term_arr;
			$c->log->debug('GEOPOSTCODE AREA: '.$area);
			my $base_url;
			switch ($area) {
				case (289) {
					$base_url = 'http://www.montevideo.gub.uy/ubicacionesRestProd/';
					$response = postcode_montevideo(\@term_arr);
				}
				case (255) {
					$c->log->debug('GEOPOSTCODE 255 ');
					$base_url = 'http://gis.rivera.gub.uy/gisrivera/incphp/xajax/x_suggest.php';
					$response = postcode_rivera(\@term_arr, $c);
				}
				else {
					$response = postcode_montevideo(\@term_arr);
				}
			}
			$c->log->debug('GEOPOSTCODE AREAS: '.Dumper(\@term_arr));
		}
		$c->log->debug(qq/GEOPOSTCODE FAIL/) if (!$response->{error} && !$response->{latitude});
    $c->log->debug(qq/GEOPOSTCODE FIN/);
		#$c->log->debug(Dumper($response));
    return $response;
}

sub postcode_montevideo {
	#my ( $term_arr, $c ) = @_;
	my $term_arr = shift;
	my $response = {};
	my @addresses;
	my $req;
	my $last = 0;
	my @term_arr = @{$term_arr};

	if ( scalar @term_arr < 2 ){
		$req = HTTP::Request->new( GET => 'http://www.montevideo.gub.uy/ubicacionesRestProd/calles?nombre='.$term_arr[0]);
	}
	else{
		if ( scalar @term_arr < 3){
				$req = HTTP::Request->new( GET => 'http://www.montevideo.gub.uy/ubicacionesRestProd/cruces/'.$term_arr[0].'/?nombre='.$term_arr[1]);
		}
		else{
			if ($term_arr[2] eq 'door'){
				$req = HTTP::Request->new( GET => 'http://www.montevideo.gub.uy/ubicacionesRestProd/direccion/'.$term_arr[0].'/'.$term_arr[1]);
			}
			else{
				$req = HTTP::Request->new( GET => 'http://www.montevideo.gub.uy/ubicacionesRestProd/esquina/'.$term_arr[0].'/'.$term_arr[1]);
			}
			$last = 1;
		}
	}
	my $ua = LWP::UserAgent->new;
	my $res = $ua->request( $req );
	if ( $res->is_success ) {
		my $addr_content = JSON->new->utf8->allow_nonref->decode($res->decoded_content);
		if ( $last ){
			$response->{latitude} = $addr_content->{geoJSON}->{coordinates}[0];
			$response->{longitude} = $addr_content->{geoJSON}->{coordinates}[1];
			return $response;
		}
		else {
			foreach ( @{$addr_content} ) {
				push @addresses, { address => $_->{nombre}, latitude => $_->{codigo}, longitude => '' };
			}
		}
	}
	else {
		$response->{error} = 0;
	}
	$response->{error} = \@addresses;
	return $response;
}

sub postcode_rivera {
	my ( $term_arr, $c ) = @_;
	#my $term_arr = shift;
	my $response = {};
	my @addresses;
	my $req;
	my $last = 0;
	my @term_arr = @{$term_arr};


	##GET PHPSESSID
	my $base_url = 'http://gis.rivera.gub.uy/';
	my $uri = URI->new( $base_url );
	my $ua = LWP::UserAgent->new;
	$uri->path( 'gisrivera/map.phtml' );
	my $reqToGetId_first = POST $uri->as_string;
	my $resToGetId_first = $ua->request( $reqToGetId_first );
	my $cookie = $resToGetId_first->header('set-cookie');
	my @cookies_values = split(';', $cookie);
	my $phpsessid = $cookies_values[0];
	##CREATE A HEADER WITH ID
	my $headers = HTTP::Headers->new(
		Cookie => $phpsessid,
	);
	$ua->default_headers($headers);
	##INVOKE x_toc_update
	$uri->path( 'gisrivera/incphp/xajax/x_toc_update.php');
	my $reqUpdateToc = POST $uri->as_string.'?'. $phpsessid,[dummy => 'dummy' ];
	my $resUpdateToc = $ua->request( $reqUpdateToc );
	##Set Search TYPE PATH IN GIS SERVER
	$uri->path('gisrivera/incphp/xajax/x_search.php');
	my $reqSetType = POST $uri->as_string.'?'.$phpsessid.'&action=searchitem&searchitem=rivera_cruce_calles_rivera',[dummy => 'dummy' ];
	my $resSetType = $ua->request( $reqSetType );
	##NOW CAN PROCEED TO SEARCH
	$uri->path( 'gisrivera/incphp/xajax/x_search.php' );
	$uri->query_form( action => 'searchitem', searchitem => 'rivera_cruce_calles_rivera');
	#$ua->default_headers($headers);
	if ( scalar @term_arr < 2 ){
		$uri->path( 'gisrivera/incphp/xajax/x_suggest.php' );
		$uri->query_form( searchitem => 'rivera_cruce_calles_rivera', fldname => 'nom_calle_ini');
		$req = POST $uri->as_string,[ q => $term_arr[0],	limit => 10 ];
	}
	else{
		if ( scalar @term_arr < 3){
			$uri->path( 'gisrivera/incphp/xajax/x_suggest.php' );
			$uri->query_form( searchitem => 'rivera_cruce_calles_rivera', fldname => 'nom_calle_fin');
			$req = POST $uri->as_string,[
				dependfldval_nom_calle_ini => $term_arr[0],
				q => $term_arr[1] ,
				limit => 10,
			];
		}
		else{
			$uri->path( 'gisrivera/incphp/xajax/x_info.php' );
			if ($term_arr[2] eq 'door'){
				$req = POST $uri->as_string,[
					nombre => $term_arr[0],
					puerta => $term_arr[1] ,
					findlist => 0,
					searchitem => 'rivera_nro_puerta',
					mode => 'search',
				];
			}
			else{
				$req = POST $uri->as_string,[
					nom_calle_ini => $term_arr[0],
					nom_calle_fin => $term_arr[1] ,
					findlist => 0,
					searchitem => 'rivera_cruce_calles_rivera',
					mode => 'search',
				];
			}
			$last = 1;
		}
	}
	my $res = $ua->request( $req );
	if ( $res->is_success ) {
		if ( $last ){
			my $addr_content = JSON->new->utf8->allow_nonref->decode($res->decoded_content);
			if ( $addr_content->{queryResult} ){
				my $addr = $addr_content->{queryResult}[1];
				my @coords = split(/\+/,$addr->{allextent});
				$response->{latitude} = ($coords[0]+$coords[2])/2;
				$response->{longitude} = ($coords[1]+$coords[3])/2;
				return $response;
			}
			else {
				$response->{error} = 0;
			}
		}
		else {
			foreach ( split(/\n/,$res->decoded_content) ) {
				push @addresses, { address => $_, latitude => $_, longitude => '' };
			}
		}
	}
	else {
		$response->{error} = 0;
	}
	$response->{error} = \@addresses;
	return $response;
}

#DEADLINES
sub use_deadlines { 1 }

my %public_holidays = map { $_ => 1 } (
    '1-1', '1-6', '2-8', '2-9', '3-24', '3-25', '4-18', '5-1','5-16', '6-19', '7-18', '8-25', '10-10','11-2', '12-25'
);

sub is_public_holiday {
    my $dt = shift;
    return $public_holidays{$dt->mon().'-'.$dt->day()};
}

sub is_weekend {
    my $dt = shift;
    return $dt->dow > 5;
}

sub to_working_days_date {
	my ( $self, $dt, $days ) = @_;
    while ( $days > 0 ) {
        $dt->subtract ( days => 1 );
        next if is_public_holiday($dt) or is_weekend($dt);
        $days--;
    }
    return $dt;

}

sub report_sent_confirmation_email { 1 }
sub admin_show_creation_graph { 0 }

sub skip_update_check { 1 }

sub send_comptroller_agregate { 0 }

sub send_comptroller_repeat { 0 }

sub send_council_agregate { 0 }

sub send_council_repeat { 0 }

sub skip_send_after {
	my $self = shift;
    my $row  = shift;

    return 0 unless $row->send_fail_count;

    return $row->send_fail_count > 24;
}

sub use_tasks { 1 }

sub update_on_view { 0 }

sub begining_date {
	return DateTime->new(
		year  =>  2014,
		month => 8,
		day   => 1,
	);
}

sub deadlines { 1 }

sub comptroller_user_ids(){
	my ( $self, $body_id ) = @_;

	my $bodies_comprtollers = {
		4 => [1731,1682,1],
		1 => [1,1]
	};
	return $bodies_comprtollers->{$body_id};
}

sub default_map_zoom { return 3; }

1;
