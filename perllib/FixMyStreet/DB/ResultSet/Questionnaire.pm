package FixMyStreet::DB::ResultSet::Questionnaire;
use base 'DBIx::Class::ResultSet';

use strict;
use warnings;
use Encode;
use Utils;
use mySociety::EmailUtil;
use Data::Dumper;

sub send_questionnaires {
    my ( $rs, $params ) = @_;
    $rs->send_questionnaires_period( '4 weeks', $params );
    $rs->send_questionnaires_period( '26 weeks', $params )
        if $params->{site} eq 'emptyhomes';
}

sub send_questionnaires_period {
    my ( $rs, $period, $params ) = @_;

    # Select all problems that need a questionnaire email sending
    my $q_params = {
        state => [ FixMyStreet::DB::Result::Problem::visible_states() ],
        whensent => [
            '-and',
            { '!=', undef },
            { '<', \"ms_current_timestamp() - '$period'::interval" },
        ],
        send_questionnaire => 1,
    };
    # FIXME Do these a bit better...
    if ($params->{site} eq 'emptyhomes' && $period eq '4 weeks') {
        $q_params->{'(select max(whensent) from questionnaire where me.id=problem_id)'} = undef;
    } elsif ($params->{site} eq 'emptyhomes' && $period eq '26 weeks') {
        $q_params->{'(select max(whensent) from questionnaire where me.id=problem_id)'} = { '!=', undef };
    } else {
        $q_params->{'-or'} = [
            '(select max(whensent) from questionnaire where me.id=problem_id)' => undef,
            '(select max(whenanswered) from questionnaire where me.id=problem_id)' => { '<', \"ms_current_timestamp() - '$period'::interval" }
        ];
    }

    my $unsent = FixMyStreet::App->model('DB::Problem')->search( $q_params, {
        order_by => { -desc => 'confirmed' }
    } );

    while (my $row = $unsent->next) {

        my $cobrand = FixMyStreet::Cobrand->get_class_for_moniker($row->cobrand)->new();
        $cobrand->set_lang_and_domain($row->lang, 1);

        # Not all cobrands send questionnaires
        next unless $cobrand->send_questionnaires;
        next if $row->is_from_abuser;

        # Cobranded and non-cobranded messages can share a database. In this case, the conf file
        # should specify a vhost to send the reports for each cobrand, so that they don't get sent
        # more than once if there are multiple vhosts running off the same database. The email_host
        # call checks if this is the host that sends mail for this cobrand.
        next unless $cobrand->email_host;

        my $template;
        if ($params->{site} eq 'emptyhomes') {
            ($template = $period) =~ s/ //;
            $template = Utils::read_file( FixMyStreet->path_to( "templates/email/emptyhomes/" . $row->lang . "/questionnaire-$template.txt" )->stringify );
        } else {
            $template = FixMyStreet->path_to( "templates", "email", $cobrand->moniker, $row->lang, "questionnaire.txt" )->stringify;
            $template = FixMyStreet->path_to( "templates", "email", $cobrand->moniker, "questionnaire.txt" )->stringify
                unless -e $template;
            $template = FixMyStreet->path_to( "templates", "email", "default", "questionnaire.txt" )->stringify
                unless -e $template;
            $template = Utils::read_file( $template );
        }

        my %h = map { $_ => $row->$_ } qw/name title detail category/;
        $h{created} = Utils::prettify_duration( time() - $row->confirmed->epoch, 'week' );

        my $questionnaire = FixMyStreet::App->model('DB::Questionnaire')->create( {
            problem_id => $row->id,
            whensent => \'ms_current_timestamp()',
        } );

        # We won't send another questionnaire unless they ask for it (or it was
        # the first EHA questionnaire.
        $row->send_questionnaire( 0 )
            if $params->{site} ne 'emptyhomes' || $period eq '26 weeks';

        my $token = FixMyStreet::App->model("DB::Token")->new_result( {
            scope => 'questionnaire',
            data  => $questionnaire->id,
        } );
        $h{url} = $cobrand->base_url($row->cobrand_data) . '/Q/' . $token->token;

        my $sender = FixMyStreet->config('DO_NOT_REPLY_EMAIL');
        my $sender_name = _($cobrand->contact_name);

        print "Sending questionnaire " . $questionnaire->id . ", problem "
            . $row->id . ", token " . $token->token . " to "
            . $row->user->email . "\n"
            if $params->{verbose};

        my $result = FixMyStreet::App->send_email_cron(
            {
                _template_ => $template,
                _parameters_ => \%h,
                _line_indent => $cobrand->email_indent,
                To => [ [ $row->user->email, $row->name ] ],
                From => [ $sender, $sender_name ],
            },
            $sender,
            [ $row->user->email ],
            $params->{nomail}
        );
        if ($result == mySociety::EmailUtil::EMAIL_SUCCESS) {
            print "  ...success\n" if $params->{verbose};
            $row->update();
            $token->insert();
        } else {
            print " ...failed\n" if $params->{verbose};
            $questionnaire->delete;
        }
    }
}

sub timeline {
    my ( $rs, $restriction ) = @_;

    return $rs->search(
        {
            -or => {
                whenanswered => { '>=', \"ms_current_timestamp()-'7 days'::interval" },
                'me.whensent'  => { '>=', \"ms_current_timestamp()-'7 days'::interval" },
            },
            %{ $restriction },
        },
        {
            -select => [qw/me.*/],
            prefetch => [qw/problem/],
        }
    );
}

sub summary_count {
    my ( $rs, $restriction ) = @_;

    return $rs->search(
        $restriction,
        {
            group_by => [ \'whenanswered is not null' ],
            select   => [ \'(whenanswered is not null)', { count => 'me.id' } ],
            as       => [qw/answered questionnaire_count/],
            join     => 'problem'
        }
    );
}

sub send_base_users {
  my ( $rs, $params ) = @_;

  print "\n ARRANCA \n";
  my $cobrand = FixMyStreet::Cobrand->get_class_for_moniker('pormibarrio')->new();
  my $template = FixMyStreet->path_to( "templates", "email", 'pormibarrio', "external_questionnaire.txt" )->stringify;
  $template = FixMyStreet->path_to( "templates", "email", "default", "external_questionnaire.txt" )->stringify
    unless -e $template;
  $template = Utils::read_file($template);
  my $sender = FixMyStreet->config('DO_NOT_REPLY_EMAIL');
  my $sender_name = $cobrand->contact_name;
  print "\n VA A QUERY \n";
  my $h;
  if ( $params->{type} eq 'users_reporting' ) {
    my $users = FixMyStreet::App->model('DB::Problem')->search( {}, {
      select => ['users.id'],
      group_by => ['users.id'],
      order_by => { -desc => 'users.id' },
      join => 'users',
      '+select' => ['users.name', 'users.email'],
    } );
    #@users = map { { $_->get_columns } } @users;
    while ( my $userref = $users->next ) {
      $h = {
        name => $userref->users->get_column('name'),
        signature => 'Equipo de <a href="http://datauy.org">DATA</a>',
      };#map { $_ => $row->$_ } qw/name title detail category/;
      my $result = FixMyStreet::App->send_email_cron(
          {
              _template_ => $template,
              _parameters_ => $h,
              _line_indent => $cobrand->email_indent,
              To => [ [ $userref->users->get_column('email'), $userref->users->get_column('name')] ],
              From => [ $sender, $sender_name ],
          },
          $sender,
          [ $userref->users->get_column('email') ],
      );
      if ($result == mySociety::EmailUtil::EMAIL_SUCCESS) {
          print "  ...success sending mail to ".$userref->users->get_column('email')."\n"; #if $params->{verbose};
      } else {
          print " ...failed sending mail to ".$userref->users->get_column('email')."\n"; #if $params->{verbose};
      }
    }
  }
  else {
    return 0 if ( $params->{type} eq '' );
  }
}
1;
