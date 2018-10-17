package FixMyStreet::App::Controller::Stats;
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

sub stats : Path : Args(0) {
    my ( $self, $c ) = @_;
    $c->log->debug("\n ENTRA A STATS \n");
    my ( $end_date, @errors );
    my $formatter = DateTime::Format::Strptime->new( pattern => '%d/%m/%Y' );
    my $parser = DateTime::Format::Strptime->new( pattern => '%m-%d-%Y' );
    my $now = DateTime->now(formatter => $formatter);
    my $now_start = DateTime->now(formatter => $formatter);
    #Start date mandatory
    my $start_date = $formatter->parse_datetime( $c->req->param('start_date') );
    if ( !$c->req->param('start_date') ) {
        if ( $c->req->param('end_date') ){
            push @errors, _('Invalid start date');
            $c->stash->{errors} = \@errors;
            return 1;
        }
        else {
            return 1;
        }
    }

    if ( $c->req->param('last_week') ){
        $end_date = $now;
        $start_date = $now_start->subtract(days => 7);
    }
    elsif ( $c->req->param('last_month') ){
        $end_date = $now;
        $start_date = $now_start->subtract(months => 1);
    }
    elsif ( $c->req->param('last_six_months') ){
        $end_date = $now;
        $start_date = $now_start->subtract(months => 6);
    }
    elsif ( $c->req->param('all') ){
        $end_date = $now;
    }
    else{
        if ( !$c->req->param('end_date') ){
            $end_date = $now;
        }
        else{
            $end_date = $formatter->parse_datetime( $c->req->param('end_date') ) ;
        }
    }
    $c->log->debug($end_date.'<--END TIME START-->'.$start_date);

    $c->stash->{start_date} = $start_date;
    $c->stash->{end_date} = $end_date;
    $c->stash->{page} = 'stats';
}

sub stats_map : Path('stats_map') {
  my ( $self, $c ) = @_;

  $c->log->debug("\n STATS VA A MAPA \n");
  FixMyStreet::Map::display_map(
    $c,
    latitude  => '-34.8888959179138',
    longitude => '-56.126899068543',
    any_zoom  => 1,
    #pins      => $pins
  );
}

__PACKAGE__->meta->make_immutable;

1;
