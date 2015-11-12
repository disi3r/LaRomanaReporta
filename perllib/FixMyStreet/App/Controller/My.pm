package FixMyStreet::App::Controller::My;
use Moose;
use namespace::autoclean;
use Data::Dumper;
use Email::Valid;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

FixMyStreet::App::Controller::My - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index

=cut

sub my : Path : Args(0) {
    my ( $self, $c ) = @_;

    $c->detach( '/auth/redirect' ) unless $c->user;

    my $pins = [];
    my $problems = {};

    my $params = {
        state => [ FixMyStreet::DB::Result::Problem->visible_states() ],
    };
    $params = {
        %{ $c->cobrand->problems_clause },
        %$params
    } if $c->cobrand->problems_clause;

    my $rs = $c->user->problems->search( $params, {
        order_by => { -desc => 'confirmed' },
        rows => 50
    } );

    my %categories;
    my @categories_array = $c->model('DB::Contact')->all;
    foreach (@categories_array) {
        $categories{$_->category} = $_->group_id;
    }

    while ( my $problem = $rs->next ) {
        push @$pins, {
            latitude  => $problem->latitude,
            longitude => $problem->longitude,
            colour    => $c->cobrand->pin_colour( $problem, 'my', $c, \%categories ),
            id        => $problem->id,
            title     => $problem->title,
        };
        my $state = $problem->is_fixed ? 'fixed' : $problem->state eq 'in progress' ? 'in_progress' : 'confirmed';

        push @{ $problems->{$state} }, $problem;
    }
    $c->stash->{problems} = $problems;

    $rs = $c->user->comments->search(
        { state => 'confirmed' },
        {
            order_by => { -desc => 'confirmed' },
            rows => 50
        } );
    my @updates = $rs->all;
    $c->stash->{updates} = \@updates;

    #Get problems alert
    my $alert_problems_ids = [];
    $c->log->debug('VAN ALERTS');
    $c->log->debug(ref($alert_problems_ids));
    my @alerts = $c->user->alerts->search( {
        alert_type   => 'new_updates',
        whendisabled => undef,
        confirmed    => 1
        },{
        order_by     => 'id'
        } )->all;
    @alerts = map { { $_->get_columns } } @alerts;
    foreach ( @alerts ) {
        if ($_->{parameter}){
            push $alert_problems_ids, $_->{parameter};
            $c->log->debug($_->{parameter});
        }
    }
    $c->log->debug('VAN ALERTS ARRAY');
    $c->log->debug(Dumper($alert_problems_ids));
    $c->log->debug(ref($alert_problems_ids));
    my @alert_problems = $c->model('DB::Problem')->search({
        id => { -IN => $alert_problems_ids },
        user_id => { '!=' => $c->user->id }
        });
    $c->stash->{alert_problems} = \@alert_problems;

    $c->stash->{page} = 'my';
    FixMyStreet::Map::display_map(
        $c,
        latitude  => $pins->[0]{latitude},
        longitude => $pins->[0]{longitude},
        pins      => $pins,
        any_zoom  => 1,
    )
        if @$pins;
}

sub edit : Path('edit'){
    my ( $self, $c ) = @_;
    $c->detach( 'redirect' ) unless $c->user;

    # If not a post then no submission
    return unless $c->req->method eq 'POST';
    $c->stash->{page} = 1;
    #Proces FB & TW vinculations
    if ( $c->req->params->{'facebook_unlink'} || $c->req->params->{'twitter_unlink'} ){
        $c->user->facebook_id(undef) if $c->req->params->{'facebook_unlink'};
        $c->user->twitter_id(undef) if $c->req->params->{'twitter_unlink'};
        $c->user->update();
        $c->stash->{messages} = _('Los cambios han sido guardados');
        return;
    }
    #Link accounts
    $c->detach('/auth/twitter_sign_in') if $c->req->params->{'twitter_link'};
    $c->detach('/auth/facebook_sign_in') if $c->req->params->{'facebook_link'};

    #Change password
    if ( $c->req->param('change-pass-submit') ) {
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
        $c->stash->{messages} = _('Your password has been changed');
        return;
    }

    #Process email
    if ($c->req->params->{'email'} and !($c->req->params->{email} eq $c->user->email)){
        my $email_checker = Email::Valid->new(
            #-mxcheck  => 1,
            #-tldcheck => 1,
            #-fqdn     => 1,
        );
        my $raw_email = lc( $c->req->param('email'));
        my $good_email = $email_checker->address($raw_email);
        if ( !$good_email ) {
            $c->stash->{email} = $raw_email;
            $c->stash->{field_errors}{email} = $raw_email ? $email_checker->details : 'missing';
            return;
        }
        #Chequea que no haya otro usuario con ese mail
        my $user = $c->model('DB::User')->find({ email => $c->req->params->{email} });
        if ( !$user ) {
            $c->user->email( $c->req->params->{email} );
        }
        else {
            $c->stash->{field_errors}{email} = _('Email is already in use.');
            return;
        }
    }
    #Process photo
    $c->forward('/photo/process_photo');
    if ( my $fileid = $c->stash->{upload_fileid} ) {
        $c->user->picture_url( '/upload/'.$fileid.'.jpeg' );
    }
    #Process identity_document
    if ( $c->req->params->{identity_document} and $c->cobrand->validate_document() ){
        my $document = $c->cobrand->validate_identity_document($c->req->params->{identity_document});
        if ($document) {
            $c->user->identity_document( $document );
        }
        else{
            $c->stash->{field_errors}{identity_document} = _('Your document is not valid');
            return;
        }
    }
    #Process other parameters
    if ( $c->req->params->{name} ){
        $c->user->name( $c->req->params->{name} );
    }
    if ( $c->req->params->{phone} ){
        $c->user->phone( $c->req->params->{phone} );
    }

    $c->stash->{user} = $c->user;
    $c->stash->{field_errors} ||= {};
    my %field_errors = $c->cobrand->user_check_for_errors( $c );

    if ( scalar keys %field_errors ){
        $c->stash->{field_errors} = \%field_errors;
        return;
    }
    #Update user
    $c->user->modified(\'ms_current_timestamp()');
    $c->user->update();
    $c->stash->{messages} = _('Los cambios han sido guardados');
    return;
}

__PACKAGE__->meta->make_immutable;

1;
