package FixMyStreet::App::Controller::Report;

use Moose;
use namespace::autoclean;
BEGIN { extends 'Catalyst::Controller'; }
use Data::Dumper;
use Open311;
use JSON;
use utf8;

=head1 NAME

FixMyStreet::App::Controller::Report - display a report

=head1 DESCRIPTION

Show a report

=head1 ACTIONS

=head2 index

Redirect to homepage unless C<id> parameter in query, in which case redirect to
'/report/$id'.

=cut

sub index : Path('') : Args(0) {
    my ( $self, $c ) = @_;

    my $id = $c->req->param('id');

    my $uri =
        $id
      ? $c->uri_for( '/report', $id )
      : $c->uri_for('/');

    $c->res->redirect($uri);
}

=head2 report_display

Display a report.

=cut

sub display : Path('') : Args(1) {
    my ( $self, $c, $id ) = @_;

    if (
        $id =~ m{ ^ 3D (\d+) $ }x         # Some council with bad email software
        || $id =~ m{ ^(\d+) \D .* $ }x    # trailing garbage
      )
    {
        return $c->res->redirect( $c->uri_for($1), 301 );
    }

    $c->forward( '_display', [ $id ] );
}

=head2 ajax

Return JSON formatted details of a report

=cut

sub ajax : Path('ajax') : Args(1) {
    my ( $self, $c, $id ) = @_;

    $c->stash->{ajax} = 1;
    $c->forward( '_display', [ $id ] );
}

sub _display : Private {
    my ( $self, $c, $id ) = @_;

    $c->forward( 'load_problem_or_display_error', [ $id ] );
    $c->forward( 'load_updates' );
    $c->forward( 'format_problem_for_display' );
    if ($c->cobrand->use_tasks){
        $c->forward( 'load_problem_tasks' );
    }
}

sub support : Path('support') : Args(0) {
    my ( $self, $c ) = @_;

    my $id = $c->req->param('id');

    my $uri =
        $id
      ? $c->uri_for( '/report', $id )
      : $c->uri_for('/');

    if ( $id && $c->cobrand->can_support_problems && $c->user && $c->user->from_body ) {
        $c->forward( 'load_problem_or_display_error', [ $id ] );
        $c->stash->{problem}->update( { interest_count => \'interest_count +1' } );
    }
    $c->res->redirect( $uri );
}

sub load_problem_or_display_error : Private {
    my ( $self, $c, $id ) = @_;

    # try to load a report if the id is a number
    my $problem
      = ( !$id || $id =~ m{\D} ) # is id non-numeric?
      ? undef                    # ...don't even search
      : $c->cobrand->problems->find( { id => $id } );

    # check that the problem is suitable to show.
    if ( !$problem || ($problem->state eq 'unconfirmed' && !$c->cobrand->show_unconfirmed_reports) || $problem->state eq 'partial' ) {
        $c->detach( '/page_error_404_not_found', [ _('Unknown problem ID') ] );
    }
    elsif ( $problem->state eq 'hidden' ) {
        $c->detach(
            '/page_error_410_gone',
            [ _('That report has been removed from FixMyStreet.') ]    #
        );
    } elsif ( $problem->non_public ) {
        if ( !$c->user || $c->user->id != $problem->user->id ) {
            $c->detach(
                '/page_error_403_access_denied',
                [ sprintf(_('That report cannot be viewed on %s.'), $c->cobrand->site_title) ]    #
            );
        }
    }
    #Check if cobrand allows update when viewing and that problem has flag has_updates
    if ( $c->cobrand->update_on_view ){
        my $body = ( values $problem->bodies )[0];
        my $open311 = Open311->new( endpoint => $body->endpoint );
        my $prequest = $open311->get_service_custom_meta_info($problem->external_id);
        if ( ref $prequest eq 'HASH' && exists $prequest->{request} ){
            #update general information
            $c->log->debug( "\n HAY UPDATE:\n" );
            $c->log->debug( Dumper($prequest->{request}) );
            $c->log->debug( "\n TERMINA UPDATE:\n\n" );
            #update tasks
        }
    }

    $c->stash->{problem} = $problem;
    return 1;
}

sub load_updates : Private {
    my ( $self, $c ) = @_;

    my $updates = $c->model('DB::Comment')->search(
        { problem_id => $c->stash->{problem}->id, state => 'confirmed' },
        { join => 'users', order_by => 'confirmed' }
    );

    my $questionnaires = $c->model('DB::Questionnaire')->search(
        {
            problem_id => $c->stash->{problem}->id,
            whenanswered => { '!=', undef },
            old_state => 'confirmed', new_state => 'confirmed',
        },
        { order_by => 'whenanswered' }
    );

    my @combined;
    while (my $update = $updates->next) {
        push @combined, [ $update->confirmed, $update ];
    }
    while (my $update = $questionnaires->next) {
        push @combined, [ $update->whenanswered, $update ];
    }
    @combined = map { $_->[1] } sort { $a->[0] <=> $b->[0] } @combined;
    $c->stash->{updates} = \@combined;

    return 1;
}

sub format_problem_for_display : Private {
    my ( $self, $c ) = @_;

    my $problem = $c->stash->{problem};

    ( $c->stash->{short_latitude}, $c->stash->{short_longitude} ) =
      map { Utils::truncate_coordinate($_) }
      ( $problem->latitude, $problem->longitude );

    unless ( $c->req->param('submit_update') ) {
        $c->stash->{add_alert} = 1;
    }

    $c->stash->{extra_name_info} = $problem->bodies_str && $problem->bodies_str eq '2482' ? 1 : 0;

    $c->forward('generate_map_tags');

    $c->log->debug("\n\nARRANCA UPDATE\n");
    $c->log->debug(Dumper($c->stash->{updates}));
    $c->log->debug("\n\nTERMINA UPDATE\n");

    if ( $c->stash->{ajax} ) {
        $c->stash->{template} = 'report/mobile_display.html';
        return 1;
    }
    #stash contacts so they can be changed
    my @contacts = $c->model('DB::Contact')->not_deleted->search( { body_id => [ $problem->bodies_str ] } )->all;

    my @categories;
    foreach my $contact (@contacts) {
        push @categories, $contact->category;
    }
    $c->stash->{categories} = \@categories;
    $c->stash->{state_t} = $problem->as_hashref($c)->{state_t};
    return 1;
}

sub generate_map_tags : Private {
    my ( $self, $c ) = @_;

    my $problem = $c->stash->{problem};

	my $colour = $c->cobrand->moniker eq 'zurich'? $c->cobrand->pin_colour($problem) : 'yellow';

	my @category_array = $c->model('DB::Contact')->search({ category => $problem->category })->all;
	if ( scalar @category_array => 1 ) {
		if ( $category_array[0]->group_id ){
            $colour = $problem->category_icon( $category_array[0]->group_id );
        }
	}

    $c->stash->{page} = 'report';
    FixMyStreet::Map::display_map(
        $c,
        latitude  => $problem->latitude,
        longitude => $problem->longitude,
        pins      => $problem->used_map
        ? [ {
            latitude  => $problem->latitude,
            longitude => $problem->longitude,
            colour    => $colour,
            type      => 'big',
          } ]
        : [],
    );

    return 1;
}

sub delete :Local :Args(1) {
    my ( $self, $c, $id ) = @_;

    $c->forward( 'load_problem_or_display_error', [ $id ] );
    my $p = $c->stash->{problem};

    my $uri = $c->uri_for( '/report', $id );

    return $c->res->redirect($uri) unless $c->user_exists;

    my $body = $c->user->obj->from_body;

    if ($body){
        return $c->res->redirect($uri) unless $p->bodies->{$body->id};
    }
    else {
        return $c->res->redirect($uri) unless $c->user->id == $p->user_id;
    }

    $p->state('hidden');
    $p->lastupdate( \'ms_current_timestamp()' );
    $p->update;

    $c->model('DB::AdminLog')->create( {
        admin_user => $c->user->email,
        object_type => 'problem',
        action => 'state_change',
        object_id => $id,
    } );

    return $c->res->redirect($uri);
}

sub delete_ajax : Path('delete_ajax') :Args(1) {
    my ( $self, $c, $id ) = @_;

    $c->forward( 'load_problem_or_display_error', [ $id ] );
    my $p = $c->stash->{problem};

    if($c->user_exists){
    }else{
      $c->stash->{ json_response } = { errors => _('El usuario no existe') };
      $c->stash->{ json_response } .= { message => _('El usuario no existe'), result => 0 };
      $c->forward('send_json_response');
    }

    my $body = $c->user->obj->from_body;

    if ($body){
      if($p->bodies->{$body->id}){
      }else{
        $c->stash->{ json_response } = { errors => _('Hubo un error al validar el reporte contra el municipio del usuario') };
        $c->stash->{ json_response } .= { message => _('Hubo un error al validar el reporte contra el municipio del usuario'), result => 0 };
        $c->forward('send_json_response');
      }
    }
    if($c->user->id != $p->user_id){
      $c->stash->{ json_response } = { errors => _('Este reporte no pertenece al usuario') };
      $c->stash->{ json_response } .= { message => _('Este reporte no pertenece al usuario'), result => 0 };
      $c->forward('send_json_response');
    }

    $p->state('hidden');
    $p->lastupdate( \'ms_current_timestamp()' );
    $p->update;

    $c->model('DB::AdminLog')->create( {
        admin_user => $c->user->email,
        object_type => 'problem',
        action => 'state_change',
        object_id => $id,
    } );

    $c->stash->{ json_response } = { success => 1 };
    $c->stash->{ json_response }->{result} = 1;
    $c->forward('send_json_response');
}

sub send_json_response : Private {
    my ( $self, $c ) = @_;

    my $body = JSON->new->utf8(1)->encode(
        $c->stash->{json_response},
    );
    $c->res->content_type('application/json; charset=utf-8');
    $c->res->body($body);
}

sub load_problem_tasks : Private {
    my ( $self, $c ) = @_;

    my $p = $c->stash->{problem};

    my @tasks = $c->model('DB::Task')->search({ problem_id => $p->id })->all;

    #@tasks = map { { $_->get_columns } } @tasks;

    $c->stash->{tasks} = \@tasks;
    $c->log->debug("\n\nARRANCA TASK\n");
    #$c->log->debug(Dumper(@tasks));
    $c->log->debug("\nTERMINA TASK\n\n");
    return 1;
}

__PACKAGE__->meta->make_immutable;

1;
