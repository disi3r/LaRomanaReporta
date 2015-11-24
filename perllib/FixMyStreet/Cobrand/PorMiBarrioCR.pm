package FixMyStreet::Cobrand::PorMiBarrioCR;
use base 'FixMyStreet::Cobrand::Default';

use strict;
use warnings;
use JSON;
use HTTP::Request::Common;
use Data::Dumper;
use LWP::UserAgent;
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

sub validate_document {0}

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
			my $pin = 'group-'.$categories->{$category_name};
			if ($p->is_fixed){
				$pin .= '-resuelto';
			}
			else{
				if ($p->state eq 'in progress'){
					$pin .= '-proceso';
				}
			}
			return $pin;
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

sub site_title { return 'PorMiBarrioCR'; }

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

#DEADLINES
sub deadlines { 1 }

my %public_holidays = map { $_ => 1 } (
    '1-1', '4-2', '4-3', '4-11', '5-1', '6-25', '8-15', '9-15','12-25',
);

sub is_public_holiday {
    my $dt = shift;
    return $public_holidays{$dt->mon().'-'.$dt->day()};
}

sub is_weekend {
    my $dt = shift;
    return $dt->dow > 5;
}

sub to_working_days_date{
	my ( $self, $dt, $days ) = @_;
    while ( $days > 0 ) {
        $dt->subtract ( days => 1 );
        next if is_public_holiday($dt) or is_weekend($dt);
        $days--;
    }
    return $dt;

}

=head2 problem_rules

Response is {group_id => [<objects arranged by time>]}

=cut

sub problem_rules {
	return (
		'1' => [
			{
				'max_time' => 10,
				'class' => 'comptroller_overdue',
				'action' => 'email'
			},
			{
				'max_time' => 8,
				'class' => 'problem-alert'
			},
			{
				'max_time' => 6,
				'class' => 'problem-warning'
			}
		],
		'2' => [
			{
				'max_time' => 10,
				'class' => 'comptroller_overdue',
				'action' => 'email'
			},
			{
				'max_time' => 8,
				'class' => 'problem-alert'
			},
			{
				'max_time' => 6,
				'class' => 'problem-warning'
			}
		],
		'3' => [
			{
				'max_time' => 10,
				'class' => 'comptroller_overdue',
				'action' => 'email'
			},
			{
				'max_time' => 8,
				'class' => 'problem-alert'
			},
			{
				'max_time' => 6,
				'class' => 'problem-warning'
			}
		],
		'4' => [
			{
				'max_time' => 10,
				'class' => 'comptroller_overdue',
				'action' => 'email'
			},
			{
				'max_time' => 8,
				'class' => 'problem-alert'
			},
			{
				'max_time' => 6,
				'class' => 'problem-warning'
			}
		],
		'5' => [
			{
				'max_time' => 10,
				'class' => 'comptroller_overdue',
				'action' => 'email'
			},
			{
				'max_time' => 8,
				'class' => 'problem-alert'
			},
			{
				'max_time' => 6,
				'class' => 'problem-warning'
			}
		],
		'6' => [
			{
				'max_time' => 10,
				'class' => 'comptroller_overdue',
				'action' => 'email'
			},
			{
				'max_time' => 8,
				'class' => 'problem-alert'
			},
			{
				'max_time' => 6,
				'class' => 'problem-warning'
			}
		]
	);
}
sub report_sent_confirmation_email { 1; }
sub admin_show_creation_graph { 0 }

sub skip_update_check { 1 }

sub send_comptroller_agregate { 0 }

sub send_comptroller_repeat { 0 }
1;
