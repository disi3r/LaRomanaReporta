package FixMyStreet::App::Controller::Auth;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use Email::Valid;
use Net::Domain::TLD;
use mySociety::AuthToken;
use JSON;
use Net::Facebook::Oauth2;
use Net::Twitter::Lite::WithAPIv1_1;
use Digest::HMAC_SHA1;
use Data::Dumper;
=head1 NAME

FixMyStreet::App::Controller::Auth - Catalyst Controller

=head1 DESCRIPTION

Controller for all the authentication related pages - create account, sign in,
sign out.

=head1 METHODS

=head2 index

Present the user with a sign in / create account page.

=cut

sub general : Path : Args(0) {
    my ( $self, $c ) = @_;
    my $req = $c->req;
    $c->detach( 'redirect_on_signin', [ $req->param('r') ] )
        if $c->user && $req->param('r');

    # all done unless we have a form posted to us
    return unless $req->method eq 'POST';

    # decide which action to take
    $c->detach('facebook_sign_in') if $req->param('facebook_sign_in');
    $c->detach('twitter_sign_in') if $req->param('twitter_sign_in') || $req->param('twitter_link');

    $c->detach('email_sign_in') if $req->param('email_sign_in') || $c->req->param('name') || $c->req->param('password_register');

    $c->forward( 'sign_in' ) && $c->detach( 'redirect_on_signin', [ $req->param('r') ] );

}

=head2 sign_in

Allow the user to sign in with a username and a password.

=cut

sub sign_in : Private {
    my ( $self, $c, $email ) = @_;

    $email        ||= $c->req->param('email')            || '';
    $email        ||= $c->req->param('form_email')       || '';

    my $password    = $c->req->param('password_sign_in') || '';
    my $remember_me = $c->req->param('remember_me')      || 0;

    # Sign out just in case
    $c->logout();

    if ( $email && $password && $c->authenticate( { email => $email, password => $password } ) )
    {
        # unless user asked to be remembered limit the session to browser
        $c->set_session_cookie_expire(0)
          unless $remember_me;

        return 1;
    }

    $c->stash(
        sign_in_error => 1,
        email => $email,
        remember_me => $remember_me,
    );
    return;
}

=head2 email_sign_in

Email the user the details they need to sign in. Don't check for an account - if
there isn't one we can create it when they come back with a token (which
contains the email addresss).

=cut

sub email_sign_in : Private {
    my ( $self, $c ) = @_;
    $c->log->debug('EMAIL SIGN IN: '.$c->req->param('r') );
    # check that the email is valid - otherwise flag an error
    my $raw_email = lc( $c->req->param('login_email') || $c->req->param('form_email') || '' );

    my $email_checker = Email::Valid->new(
        #-mxcheck  => 1,
        #-tldcheck => 1,
        #-fqdn     => 1,
    );

    my $good_email = $email_checker->address($raw_email);
    if ( !$good_email ) {
        $c->stash->{email} = $raw_email;
        $c->stash->{email_error} = $raw_email ? $email_checker->details : 'missing';
        return;
    }
    my $user;
    #Allow send email to login
    if ($c->req->param('login_email')){
		$c->log->debug('Envia mail para login o cambiar mail: '.$good_email);
    	$user = $c->model('DB::User')->find({ email => $good_email });
    	if (!defined $user){
    		$c->stash->{field_errors}{login_email} = _('Email is not registered');
    		return;
    	}
    }
    else{
		$c->log->debug('Nuevo usuario');
	    my $user_params = {};
	    $user_params->{email} = $good_email if $good_email;
	    $user_params->{name} = $c->req->param('name') if $c->req->param('name');
	    $user_params->{password} = $c->req->param('password_register') if $c->req->param('password_register');
      $user_params->{identity_document} = $c->req->param('identity_document') if $c->req->param('identity_document');
	    $user_params->{phone} = $c->req->param('phone') if $c->req->param('phone');
	    $user = $c->model('DB::User')->new( $user_params );
	}

  $c->stash->{field_errors} ||= {};
  $c->stash->{user} = $user;
	my %field_errors = $c->cobrand->user_check_for_errors( $c );

	#Added identity document, to be validated only if $c->cobrand->validate_document is set
  my $identity_document = '';
 	if ( $c->cobrand->validate_document ){
		if ($user->identity_document){
			$identity_document = $c->cobrand->validate_identity_document( $user->identity_document );
			if (!$identity_document){
        $c->stash->{field_errors}{identity_document} = _('Please enter a valid ID');
        return;
			}
		}
		else {
    	$c->stash->{field_errors}{identity_document} = _('Please enter your ID');
    	return;
  	}
	}

	if ( scalar keys %field_errors ){
		$c->stash->{field_errors} = \%field_errors;
		return;
	}

  my $mail_tpl;
  my $redir = scalar $c->req->param('redirect');
  if ($c->req->param('login_email')){
    $mail_tpl = 'reset-email.txt';
    $redir = $redir.'/pass';
  }
  else {
    $mail_tpl = 'login.txt';
  }
  my $token_obj = $c->model('DB::Token')->create(
    {
      scope => 'email_sign_in',
      data  => {
        email => $good_email,
        redirect => $redir,
        name => scalar $user->name,
        password => $user->password,
        phone =>  $user->phone,
        identity_document => $identity_document,
      }
    }
  );

  $c->stash->{token} = $token_obj->token;
	$c->send_email( $mail_tpl, { to => $good_email } );
  $c->stash->{template} = 'auth/token.html';
}

=head2 social_signup

Asks the user to confirm data returned from facebook/twitter and signs up the user.
TODO: user to-be information is received in the session. i'm sure there is a better way to do this :(

=cut

sub social_signup : Path('/auth/social_signup') : Args(0) {
	my ( $self, $c ) = @_;

	my $name = $c->req->param('name') if $c->req->param('name');
	my $email = $c->req->param('email') if $c->req->param('email');
	my $identity_document = $c->req->param('identity_document') if $c->req->param('identity_document');
	my $password = $c->req->param('password') if $c->req->param('password');
	my $phone = $c->req->param('phone') if $c->req->param('phone');
	my $facebook_id = $c->req->param('facebook_id') if $c->req->param('facebook_id');
	my $twitter_id = $c->req->param('twitter_id') if $c->req->param('twitter_id');
	my $picture_url = $c->req->param('picture_url') if $c->req->param('picture_url');

	my $new_user = $c->model('DB::User')->new({
		name => $name,
		email => $email,
		identity_document => $identity_document,
		phone => $phone,
		facebook_id => $facebook_id,
		twitter_id => $twitter_id,
		picture_url => $picture_url,
	});

	$c->stash->{user} = $new_user;

	$c->stash->{field_errors} ||= {};
	my %field_errors = $c->cobrand->user_check_for_errors( $c );

	#Added identity document, to be validated only if $c->cobrand->validate_document is set
   	if ( $c->cobrand->validate_document ){
		if ( defined $identity_document && $new_user->identity_document){
			$identity_document = $c->cobrand->validate_identity_document( $new_user->identity_document );
			if (!$identity_document){
		        $c->stash->{field_errors}{identity_document} = _('Please enter a valid ID');
		        return;
			}
		}
		else {
        	$c->stash->{field_errors}{identity_document} = _('Please enter your ID');
        	return;
    	}
	}

	if ( !scalar keys %field_errors ) {
		my $user = $c->model('DB::User')->find_or_create({ email => $new_user->email });

		if ( $user ) {
			my $token_data = {
				id => $user->id,
				facebook_id => $new_user->facebook_id,
				twitter_id => $new_user->twitter_id,
				name => $new_user->name,
				email => $new_user->email,
				#password => $password,
				phone => $new_user->phone,
				identity_document => $identity_document,
				picture_url => $new_user->picture_url,
			};
			if ( $password ) {
				$token_data->{password} = $password;
			}

			my $token_social_sign_up = $c->model("DB::Token")->create( {
				scope => 'email_sign_in/social',
				data => {
					%$token_data,
					return_url => $c->session->{oauth}{return_url},
					detach_to => $c->session->{oauth}{detach_to},
					detach_args => $c->session->{oauth}{detach_args},
				}
			} );

			$c->stash->{token} = $token_social_sign_up->token;
			$c->send_email( 'login.txt', { to => $new_user->email } );
			$c->stash->{template} = 'auth/token.html';
		}
	} else {
		$c->stash->{field_errors} = \%field_errors;
	}
}

=head2 token

Handle the 'email_sign_in' tokens. Find the account for the email address
(creating if needed), authenticate the user and delete the token.

=cut

sub token : Path('/M') : Args(1) {
    my ( $self, $c, $url_token ) = @_;

	# Sign out in case we are another user
	$c->logout();

    # retrieve the token
    my $token_obj = $url_token
      ? $c->model('DB::Token')->find( {
          scope => 'email_sign_in', token => $url_token
        } )
      : undef;

	if ( $token_obj ) {
		# find or create the user related to the token.
		my $data = $token_obj->data;
		my $user = $c->model('DB::User')->find_or_create( { email => $data->{email} } );
		$user->name( $data->{name} ) if $data->{name};
		$user->password( $data->{password}, 1 ) if $data->{password};
		$user->identity_document( $data->{identity_document}, 1 ) if $data->{identity_document};
		$user->phone( $data->{phone}, 1 ) if $data->{phone};
		$user->update;

		$c->authenticate( { email => $user->email }, 'no_password' );
		$c->set_session_cookie_expire(0);

		$token_obj->delete;

		# send the user to their page
		$c->detach( 'redirect_on_signin', [ $data->{redirect} ] );

	} else {
		# retrieve the social token or return
		my $token_obj = $url_token
		  ? $c->model('DB::Token')->find( {
			  scope => 'email_sign_in/social', token => $url_token
			} )
		  : undef;

		if ( !$token_obj ) {
			$c->stash->{token_not_found} = 1;
			return;
		}

		my $data = $token_obj->data;

		my $user = $c->model('DB::User')->find_or_create( { email => $data->{email} } );
		$user->name( $data->{name} );
		$user->facebook_id( $data->{facebook_id} ) if $data->{facebook_id};
		$user->twitter_id( $data->{twitter_id} ) if $data->{twitter_id};
		$user->identity_document( $data->{identity_document} );
		$user->password( $data->{password} ) if $data->{password};
		$user->phone( $data->{phone} ) if $data->{phone};
		$user->picture_url( $data->{picture_url} );
		$user->update;

		$c->authenticate( { email => $data->{email} }, 'no_password' );
		$c->set_session_cookie_expire(0);

		$token_obj->delete;

		## send the user to their page
		if ( $data->{detach_to} ) {
			$c->detach( $data->{detach_to}, $data->{detach_args} );
		} else {
			$c->detach( 'redirect_on_signin', [ $data->{return_url} ] );
		}
	}
}

=head2 facebook_sign_in

Starts the Facebook authentication sequence.

=cut

sub facebook_sign_in : Private {
	my( $self, $c ) = @_;

	my $params = $c->req->parameters;

    my $facebook_app_id = mySociety::Config::get('FACEBOOK_APP_ID', undef);
    my $facebook_app_secret = mySociety::Config::get('FACEBOOK_APP_SECRET', undef);
    my $facebook_callback_url = $c->uri_for('/auth/Facebook');

	my $fb = Net::Facebook::Oauth2->new(
		application_id => $facebook_app_id,  ##get this from your facebook developers platform
		application_secret => $facebook_app_secret, ##get this from your facebook developers platform
		callback => $facebook_callback_url,  ##Callback URL, facebook will redirect users after authintication
	);

	##there is no verifier code passed so let's create authorization URL and redirect to it
	my $url = $fb->get_authorization_url(
		scope => ['email'], ###pass scope/Extended Permissions params as an array telling facebook how you want to use this access
		display => 'page' ## how to display authorization page, other options popup "to display as popup window" and wab "for mobile apps"
	);

	my %oauth;
	$oauth{'return_url'} = $c->req->param('r');
	$oauth{'detach_to'} = $c->stash->{detach_to};
	$oauth{'detach_args'} = $c->stash->{detach_args};
	#Sync accounts
	$oauth{'facebook_link'} = $c->req->param('facebook_link') if ( $c->req->param('facebook_link') );

	###save this token in session
	$c->session->{oauth} = \%oauth;

	$c->res->redirect($url);
}

=head2 facebook_callback

Handles the Facebook callback request and completes the authentication sequence.

=cut

sub facebook_callback: Path('/auth/Facebook') : Args(0) {
	my( $self, $c ) = @_;

	my $params = $c->req->parameters;

	if ( $params->{error_code} ) {
		#Redirect to error page...
		$c->set_session_cookie_expire(0);

		#$c->res->redirect( $c->uri_for( "/" ) );

		$c->stash->{message} = 'No es posible iniciar la sesi&oacute;n en Facebook. Por favor vuelva a intetarlo m&aacute;s tarde.';
		$c->stash->{template} = 'errors/generic.html';
	}
	else {
		my $facebook_app_id = mySociety::Config::get('FACEBOOK_APP_ID', undef);
		my $facebook_app_secret = mySociety::Config::get('FACEBOOK_APP_SECRET', undef);
		my $facebook_callback_url = $c->uri_for('/auth/Facebook');

		my $fb = Net::Facebook::Oauth2->new(
			application_id => $facebook_app_id,  ##get this from your facebook developers platform
			application_secret => $facebook_app_secret, ##get this from your facebook developers platform
			callback => $facebook_callback_url,  ##Callback URL, facebook will redirect users after authintication
		);

		# you need to pass the verifier code to get access_token
		my $access_token = $fb->get_access_token( code => $params->{code} );

		# save this token in session
		$c->session->{oauth}{token} =  $access_token;

		my $info2 = $fb->get('https://graph.facebook.com/me/permissions')->as_hash();
		$c->log->debug(Dumper($info2));

		my $info = $fb->get('https://graph.facebook.com/me')->as_hash();

		$c->log->debug('>>>>>>>>>>>>>>');
		$c->log->debug(Dumper($info));

		my $name = $info->{'name'};
		my $email = $info->{'email'};
		my $uid = $info->{'id'};
		my $user = $c->model('DB::User')->find( { facebook_id => $uid } );
		$c->log->debug('FB CALLBACK FIND');
		if (!$user) {
			$c->log->debug('FB CALLBACK NO USER');
			if( $c->session->{oauth}{facebook_link} and $c->user ){
				$c->log->debug('FB CALLBACK ACTUALIZA');
				#Actualizamos la foto en caso que se quiera
				if ( !$c->session->{oauth}{not_update_photo} ){
					$c->user->picture_url( 'https://graph.facebook.com/'.$uid.'/picture?type=square' );
				}
				$c->user->facebook_id($uid);
				$c->user->update();
				#Redirect to my
				my $uri = $c->uri_for( '/my', { mf1 => 1 } );
			    $c->res->redirect( $uri );
			    $c->detach;
			}
			else{
				$c->log->debug('FB CALLBACK NUEVO');
				my $new_user = $c->model('DB::User')->new({
					name => $name,
					email => $email,
					facebook_id => $uid,
					picture_url => 'https://graph.facebook.com/'.$uid.'/picture?type=square',
				});
				$c->stash->{user} = $new_user;
				$c->stash->{template} = 'auth/social_signup.html';
			}
		}
		else {
			$c->log->debug('FB CALLBACK USER');
			if( $c->session->{oauth}{facebook_link} and $c->user ){
				$c->log->debug('FB CALLBACK REDIRECT HAY OTRO USER');
				my $uri = $c->uri_for( '/my', { mf2 => 1 } );
			    $c->res->redirect( $uri );
			    $c->detach;
			}
			else {
				$c->log->debug('FB CALLBACK FUE PARA AUTENTICAR');
				if ( $user->picture_url != 'https://graph.facebook.com/'.$uid.'/picture?type=square' and !$c->session->{oauth}{not_update_photo} ) {
					$user->picture_url( 'https://graph.facebook.com/'.$uid.'/picture?type=square' );
					$user->update();
				}
				#Autenthicate user with immedate expire
				$c->authenticate( { email => $user->email }, 'no_password' );
				$c->set_session_cookie_expire(0);
				if ($c->session->{oauth}{detach_to}){
					$c->detach($c->session->{oauth}{detach_to}, $c->session->{oauth}{detach_args});
				}
				else{
					$c->detach( 'redirect_on_signin', [ $c->session->{oauth}{return_url} ] );
				}
			}
		}
	}
}

=head2 twitter_sign_in

Starts the Twitter authentication sequence.

=cut

sub twitter_sign_in : Private {
	my( $self, $c ) = @_;
    my $twitter_key = mySociety::Config::get('TWITTER_KEY', undef);
    my $twitter_secret = mySociety::Config::get('TWITTER_SECRET', undef);
    my $twitter_callback_url = $c->uri_for('/auth/Twitter');

	my %consumer_tokens = (
		consumer_key    => $twitter_key,
		consumer_secret => $twitter_secret,
	);

	my $twitter = Net::Twitter::Lite::WithAPIv1_1->new(ssl => 1, %consumer_tokens);
    my $url = $twitter->get_authorization_url(callback => $twitter_callback_url);

	my %oauth;
	$oauth{'return_url'} = $c->req->param('r');
	$oauth{'detach_to'} = $c->stash->{detach_to};
	$oauth{'detach_args'} = $c->stash->{detach_args};
	$oauth{'token'} = $twitter->request_token;
	$oauth{'token_secret'} = $twitter->request_token_secret;
	#Sync accounts
	$oauth{'twitter_link'} = $c->req->param('twitter_link') if ($c->req->param('twitter_link'));

	###save this token in session
	$c->session->{oauth} = \%oauth;
	$c->res->redirect($url);
}

=head2 twitter_callback

Handles the Twitter callback request and completes the authentication sequence.

=cut

sub twitter_callback: Path('/auth/Twitter') : Args(0) {
	my( $self, $c ) = @_;
	my $request_token = $c->req->param('oauth_token');
    my $verifier      = $c->req->param('oauth_verifier');

    my $twitter_key = mySociety::Config::get('TWITTER_KEY', undef);
    my $twitter_secret = mySociety::Config::get('TWITTER_SECRET', undef);

    my %consumer_tokens = (
		consumer_key    => $twitter_key,
		consumer_secret => $twitter_secret,
	);

	my $oauth = $c->session->{oauth};

	my $twitter = Net::Twitter::Lite::WithAPIv1_1->new(ssl => 1, %consumer_tokens);
	$twitter->request_token($oauth->{token});
	$twitter->request_token_secret($oauth->{token_secret});

	my($access_token, $access_token_secret, $uid, $name) =
		$twitter->request_access_token(verifier => $verifier);

	my $twitter_user = $twitter->show_user($uid);
	my $user = $c->model('DB::User')->find( { twitter_id => $uid } );

	if (!$user) {
		if( $oauth->{twitter_link} and $c->user ){
			#Actualizamos la foto en caso que se quiera
			if (!$oauth->{not_update_photo}){
				$c->user->picture_url( $twitter_user->{profile_image_url} );
			}
			$c->user->twitter_id($uid);
			$c->user->update();
			#Redirect to my
			my $uri = $c->uri_for( '/my', { mt1 => 1 } );
		    $c->res->redirect( $uri );
		    $c->detach;
		}
		else{
			my $new_user = $c->model('DB::User')->new({
				name => $name,
				twitter_id => $uid,
				picture_url => $twitter_user->{profile_image_url},
			});

			$c->stash->{user} = $new_user;
			$c->stash->{template} = 'auth/social_signup.html';
		}
	}
	else {
		if( $oauth->{twitter_link} and $c->user ){
			my $uri = $c->uri_for( '/my', { mt2 => 1 } );
		    $c->res->redirect( $uri );
		    $c->detach;
		}
		else {
			if ( $user->picture_url != $twitter_user->{profile_image_url} and !$oauth->{not_update_photo} ) {
				$user->picture_url( $twitter_user->{profile_image_url} );
				$user->update();
			}
			#Autenthicate user with immedate expire
			$c->authenticate( { email => $user->email }, 'no_password' );
			$c->set_session_cookie_expire(0);
			if ($c->session->{oauth}{detach_to}){
				$c->detach($c->session->{oauth}{detach_to}, $c->session->{oauth}{detach_args});
			}
			else{
				$c->detach( 'redirect_on_signin', [ $c->session->{oauth}{return_url} ] );
			}
		}
	}
}

=head2 redirect_on_signin

Used after signing in to take the person back to where they were.

=cut


sub redirect_on_signin : Private {
    my ( $self, $c, $redirect ) = @_;
    $redirect = 'my' unless $redirect;

    if ( $c->cobrand->moniker eq 'zurich' ) {
        $redirect = 'my' if $redirect eq 'admin';
        $redirect = 'admin' if $c->user->from_body;
    }

    $c->res->redirect( $c->uri_for( "/$redirect" ) );
}

=head2 redirect

Used when trying to view a page that requires sign in when you're not.

=cut

sub redirect : Private {
    my ( $self, $c ) = @_;

    my $uri = $c->uri_for( '/auth', { r => $c->req->path } );
    $c->res->redirect( $uri );
    $c->detach;

}

=head2 change_password

Let the user change their password.

=cut

sub change_password : Local {
    my ( $self, $c ) = @_;

    $c->detach( 'redirect' ) unless $c->user;

    # FIXME - CSRF check here
    # FIXME - minimum criteria for passwords (length, contain number, etc)

    # If not a post then no submission
    return unless $c->req->method eq 'POST';

    # get the passwords
    my $new     = $c->req->param('new_password') // '';
    my $confirm = $c->req->param('confirm')      // '';

    # check for errors
    my $password_error =
       !$new && !$confirm ? 'missing'
      : $new ne $confirm ? 'mismatch'
      :                    '';

    if ($password_error) {
        $c->stash->{password_error} = $password_error;
        $c->stash->{new_password}   = $new;
        $c->stash->{confirm}        = $confirm;
        return;
    }

    # we should have a usable password - save it to the user
    $c->user->obj->update( { password => $new } );
    $c->stash->{password_changed} = 1;

}

sub ajax_change_password : Path('ajax/change_password') {
  my ( $self, $c ) = @_;

  my $return = {};
	if ( $c->req->params->{email} && $c->req->params->{password_sign_in} && $c->authenticate( { email => $c->req->params->{email}, password => $c->req->params->{password_sign_in} } ) ) {
    $c->forward('change_password');
    if ( $c->stash->{'password_changed'} ){
      $return->{result} = 1;
      $return->{message} = 'Password successfuly changed';
    }
    else {
      $return->{message} = $c->stash->{password_error} ? $c->stash->{password_error} : _('Error in password change');
      $return->{result} = 0;
      $return->{error} = 1;
    }
  }
  my $body = JSON->new->utf8(1)->encode( $return );
  $c->res->content_type('application/json; charset=utf-8');
  $c->res->body($body);

  return 1;
}

sub ajax_forgot_password : Path('ajax/forgot_password') {
  my ( $self, $c ) = @_;

  my $return = {};
	if ( $c->req->params->{login_email} ) {
    $c->forward('email_sign_in');
  }
  else {
    $c->stash->{field_errors} = _('Parameters not match');
  }
  if (scalar keys %{$c->stash->{field_errors}}){
    $return->{message} = $c->stash->{field_errors} ? $c->stash->{field_errors} : _('Error in one time login request');
    $return->{result} = 0;
    $return->{error} = 1;
  }
  else {
    $return->{result} = 1;
    $return->{message} = _('Email successfuly sended');
  }

  my $body = JSON->new->utf8(1)->encode( $return );
  $c->res->content_type('application/json; charset=utf-8');
  $c->res->body($body);

  return 1;
}

=head2 sign_out

Log the user out. Tell them we've done so.

=cut

sub sign_out : Local {
    my ( $self, $c ) = @_;
    $c->logout();
}

sub ajax_sign_in : Path('ajax/sign_in') {
    my ( $self, $c ) = @_;

    my $return = {};
    if ( $c->forward( 'sign_in' ) ) {
        $return->{name} = $c->user->name;
        $return->{phone} = $c->user->phone;
        $return->{identity_document} = $c->user->identity_document;
        if ( $c->user->from_body ){
          $return->{from_body} = $c->user->from_body->body_areas->first->area_id;
        }
        if ( $c->user->picture_url ){
        	$return->{picture_url} = $c->cobrand->base_url.$c->user->picture_url;
        }
        else {
        	$return->{picture_url} = '';
        }
    } else {
        $return->{error} = 1;
        $return->{result} = 0;
        $return->{message} = _('User or password incorrect');
    }

    my $body = JSON->new->utf8(1)->encode( $return );
    $c->res->content_type('application/json; charset=utf-8');
    $c->res->body($body);

    return 1;
}

sub ajax_sign_out : Path('ajax/sign_out') {
    my ( $self, $c ) = @_;

    $c->logout();

    my $body = JSON->new->utf8(1)->encode( { signed_out => 1 } );
    $c->res->content_type('application/json; charset=utf-8');
    $c->res->body($body);

    return 1;
}

sub ajax_check_auth : Path('ajax/check_auth') {
    my ( $self, $c ) = @_;

    my $code = 401;
    my $data = { not_authorized => 1 };

    if ( $c->user ) {
        $data = { name => $c->user->name };
        $code = 200;
    }

    my $body = JSON->new->utf8(1)->encode( $data );
    $c->res->content_type('application/json; charset=utf-8');
    $c->res->code($code);
    $c->res->body($body);

    return 1;
}

sub ajax_create_user : Path('ajax/create_user') {
	my ( $self, $c ) = @_;

	$c->forward('email_sign_in');
	my %result;

	if ( $c->stash->{field_errors} && %{$c->stash->{field_errors}} ){
		my $errors = '';
		foreach ( keys %{$c->stash->{field_errors}} ){
			$errors .= $c->stash->{field_errors}->{$_}."\n";
		}
		%result = ( result => '0', message => $errors );
	}
	else {
		$c->log->debug( "\nENTRA A OK\n\n" );
		%result = ( result => 1, message => _('Email has been sent for confirmation') );
	}

	my $body = JSON->new->utf8(1)->encode( \%result );
    $c->res->content_type('application/json; charset=utf-8');
    $c->res->body($body);

    return 1;
}

sub ajax_edit_user : Path('ajax/edit_user') {
	my ( $self, $c ) = @_;

	my %result;

	$c->log->debug("\n OBJETO: \n");
	$c->log->debug(Dumper($c->req));

	if ( $c->req->params->{email} && $c->req->params->{password_sign_in} && $c->authenticate( { email => $c->req->params->{email}, password => $c->req->params->{password_sign_in} } ) ) {
        $c->forward('/my/edit');
		if ( $c->stash->{field_errors} && %{$c->stash->{field_errors}} ){
			my $errors = '';
			foreach ( keys %{$c->stash->{field_errors}} ){
				$errors .= $c->stash->{field_errors}->{$_}."\n";
			}
			%result = ( result => '0', message => $errors );
		}
		else {
			%result = (
				result => 1,
				email => $c->user->email,
				name => $c->user->name,
				phone => $c->user->phone,
				identity_document => $c->user->identity_document,
			);
			if ( $c->user->picture_url ){
	       #%result->{picture_url} = $c->cobrand->base_url.$c->user->picture_url;
			   %result->picture_url = $c->cobrand->base_url.$c->user->picture_url;
	    }
	    else {
  	    %result->picture_url = '';
	    }
		}
  }
  else {
	   %result = ( result => 0, password => _('User or password incorrect') );
  }

	my $body = JSON->new->utf8(1)->encode( \%result );
    $c->res->content_type('application/json; charset=utf-8');
    $c->res->body($body);

    return 1;
}

=head2 check_auth

Utility page - returns a simple message 'OK' and a 200 response if the user is
authenticated and a 'Unauthorized' / 401 reponse if they are not.

Mainly intended for testing but might also be useful for ajax calls.

=cut

sub check_auth : Local {
    my ( $self, $c ) = @_;

    # choose the response
    my ( $body, $code )    #
      = $c->user
      ? ( 'OK', 200 )
      : ( 'Unauthorized', 401 );

    # set the response
    $c->res->body($body);
    $c->res->code($code);

    # NOTE - really a 401 response should also contain a 'WWW-Authenticate'
    # header but we ignore that here. The spec is not keeping up with usage.

    return;
}

__PACKAGE__->meta->make_immutable;

1;
