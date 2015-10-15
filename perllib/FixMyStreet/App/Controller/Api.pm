package FixMyStreet::App::Controller::Api;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use Email::Valid;
use JSON;
use DateTime;
use Data::Dumper;
=head1 NAME

FixMyStreet::App::Controller::Api - Catalyst Controller

=head1 DESCRIPTION

API handler

=head1 METHODS

=head2 index

Test

=cut

sub general : Path : Args(0) {
    my ( $self, $c ) = @_;
    
    $c->log->debug('ENTRA A LA API');
    print 'APIIIIII!';

    return;
}

=head2 index

Return conacts by body

=cut

sub contacts : Path : Agrs(0) {
    my ( $self, $c, $body ) = @_;
    
    $c->log->debug('ENTRA A LA API');
    print 'APIIIIII!';

    return;
}

=head2 index

Return conacts by body

=cut

sub problems : Path : Args(0) {
    my ( $self, $c ) = @_;
    my ($start_date, $end_date);
    #Validate that body is set
    my %where = (
        bodies_str => $c->stash->{body_id}
    );
    $where{areas} = { 'like', '%,' . $c->stash->{area} . ',%' }
        if $c->stash->{area};
    $where{category} = $c->stash->{category}
        if $c->stash->{category};

    #DATES
    my $parser = DateTime::Format::Strptime->new( pattern => '%Y-%m-%d' );
    my $one_day = DateTime::Duration->new( days => 1 );
    my $now = DateTime->now(formatter => $parser);

    if (length $c->stash->{start_date}){
        $start_date = $parser->parse_datetime( $c->stash->{start_date} );
    }

    if (length $c->stash->{end_date}){
        $end_date = $parser->parse_datetime( $c->stash->{end_date} ) ;
        if (length $start_date){
            $where{'-AND'} = [
                'confirmed' => { '>=', $start_date },
                'confirmed' => { '<=', $end_date + $one_day }
            ];
        }
        else{
            $where{confirmed} = { '<=', $end_date + $one_day };
        }
    }
    #Dont let ask for the hole DB
    if (!length $end_date && length $start_date){
        $where{confirmed} = { '>=', $start_date };
    }

    my $prob_where = { %where };
    #STATE
    if ( $c->stash->{state} ){
        #Verify that state isnt hidden
        if ( $c->stash->{state} eq 'hidden'){
            return;
        }
        if ( $c->stash->{state} eq 'fixed' ) {
            $prob_where->{state} = [ FixMyStreet::DB::Result::Problem->fixed_states() ];
        }
        else {
            $prob_where->{state} = $c->stash->{state};
        }
    }
    else {
        $prob_where->{state} = [ FixMyStreet::DB::Result::Problem->visible_states() ];
    }

    my $params = {
        %$prob_where,
    };

    my @problems = $c->cobrand->problems->search( $params );
    #Get deadlines
    my %deadlines = $c->cobrand->problem_rules();
    my @problems_arr;
    #Take out sensitive data
    foreach my $problem (@problems) {
        my $problem_group = $problem->category_group($c);
        if ( ($c->stash->{category_group} && $c->stash->{category_group} eq $problem_group) || !$c->stash->{category_group} ){
            my $deadline;
            if (!$problem->is_fixed){
                if ( exists $deadlines{$problem_group} ){
                    $c->log->debug('ENTRA A GRUPO DEAD');
                    foreach my $deadline_actions (@{ $deadlines{$problem_group} }){
                        if ($problem->lastupdate_council) {
                            $c->log->debug('ENTRA A GRUPO DEAD IF');
                            if ( DateTime->now->subtract( days => $deadline_actions->{max_time} )->epoch >= $problem->lastupdate_council->epoch ){
                                $deadline = $deadline_actions->{action};
                                last;
                            }
                        }
                        else{
                            if ($problem->confirmed){
                                $c->log->debug('ENTRA A GRUPO DEAD ELSE');
                                if ( DateTime->now->subtract( days => $deadline_actions->{max_time} )->epoch >= $problem->confirmed->epoch ){
                                    $deadline = $deadline_actions->{action};
                                    last;
                                }
                            }
                        }
                    }
                }
            }
            if (!length $deadline){
                $deadline = 'noDeadLine';
            }
            push @problems_arr, {$problem->get_columns};
            $problems_arr[$#problems_arr]->{deadline} = $deadline;
            $problems_arr[$#problems_arr]->{group} = $problem_group;
        }
    }
    return \@problems_arr;
}

__PACKAGE__->meta->make_immutable;

1;