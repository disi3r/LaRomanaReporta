package FixMyStreet::App::Controller::Api;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use Email::Valid;
use JSON;
use XML::Simple;
use DateTime;
use Data::Dumper;
use Digest::MD5;
use Net::CKAN;

use constant API_DEFINITIONS => qw(reports getTotals reportsByCategoryGroup reportsByState reportsEvolution reportsByCategoryState answerTimeByCategoryGroup answerTimeByState);

=head1 NAME

FixMyStreet::App::Controller::Api - Catalyst Controller

=head1 DESCRIPTION

API handler

=head1 METHODS

=head2 index

Test

=cut
my $query_key;

sub begin : Private {
  my ( $self, $c, $method ) = @_;

  $c->stash->{format} = $c->req->param('format') ? $c->req->param('format') : 'json';
  if ( $c->forward( 'validate_key' ) ){
    if (!$c->req->param('noload')) {
      #If load is 1 then all results should be loaded (stats aplication)
      my $mem_key = $c->forward('get_query_key');
      $c->stash->{query_key} = $mem_key;
      my $api_reports = Memcached::get($mem_key);
      if ( !$api_reports ){
        if ( $c->req->param('load') ){
          $c->forward( 'load_reports' );
        }
        else{
          $c->forward( 'load_problems' );
        }
      }
    }
  }
  else {
    $c->set_session_cookie_expire(0);
    $c->stash->{api_result} = {'error' => 'No es posible iniciar sesi&oacute;n genera tu api_key. Instructivo link'};
    $c->detach();
  }
}

sub end : Private {
  my ( $self, $c ) = @_;

  $c->detach( 'format_output', [$c->stash->{api_result}] );
}

sub load_reports : Private {
  my ( $self, $c ) = @_;

  $c->forward( 'load_problems' );
  for my $callback ( API_DEFINITIONS ) {
    $c->stash->{api_result} = 0;
    $c->forward( $callback );
    Memcached::set($c->stash->{query_key}.$callback, $c->stash->{api_result}, 3600);
  }
  Memcached::set($c->stash->{query_key}, 1, 3600);
}

sub validate_key : Private {
  my ( $self, $c ) = @_;

  #Dummy for now
  if ($c->user) {return 1}
  if ( $c->req->param('api_key') ){
    #my $user = $c->model('DB::User')->search( { api_key => $c->req->param('api_key') } )->first;
    #if ($user){
      #log user access
      #$c->stash->{user} = $user;
      return 1;
    #}
    #else {
    #  $c->set_session_cookie_expire(0);
  #		$c->stash->{api_result} = {'error' => 'No es posible iniciar sesi&oacute;n genera tu api_key. Instructivo link'};
  #  }
  }
  else {
    $c->set_session_cookie_expire(0);
    $c->stash->{api_result} = {'error' => 'No es posible iniciar sesi&oacute;n genera tu api_key. Instructivo link'};
  }
  return 0;
}

sub load_dates : Private {
  my ( $self, $c, $key, %where ) = @_;

  my $api_parser = DateTime::Format::Strptime->new( pattern => '%d-%m-%Y' );
  my $parser = DateTime::Format::Strptime->new( pattern => '%Y-%m-%d' );
  my $one_day = DateTime::Duration->new( days => 1 );
  my $now = DateTime->now(formatter => $parser);
  my $start_date = $c->stash->{from} ? $api_parser->parse_datetime( $c->stash->{from} ) : 0;
  my $end_date = $c->stash->{to} ? $api_parser->parse_datetime( $c->stash->{to} ) : 0;
  #DATES
  if ( $start_date || $end_date ){
    #Check end_date
    if ($end_date){
        #$end_date = $parser->parse_datetime( $end_date ) ;
        if ($start_date){
          $where{'-AND'} = [
            $key => { '>=', $parser->format_datetime($start_date) },
            $key => { '<=', $parser->format_datetime($end_date + $one_day) }
          ];
        }
        else{
          $where{$key} = { '<=', $parser->format_datetime($end_date + $one_day) };
        }
    }
    else{
      if ($start_date){
        #$start_date->set_formatter($parser);
        $where{$key} = { '>=', $parser->format_datetime($start_date) };
      }
    }
  }
  else {
    $where{'-AND'} = [
      $key => { '>=', $parser->format_datetime( $c->cobrand->begining_date() ) },
    ];
  }
  $c->stash->{from} = $start_date;
  $c->stash->{to} = $end_date;
  return \%where;
}

=head2 get_query_key
Return conacts by body
=cut
sub get_query_key : Private {
  my ( $self, $c ) = @_;

  #Llamada a cobrand
  $query_key = 'uy';
  $c->stash->{body_id} = $c->req->param('body_id') if $c->req->param('body_id');
  $c->stash->{from} = $c->req->param('from') if $c->req->param('from');
  $c->stash->{to} = $c->req->param('to') if $c->req->param('to');
  $c->stash->{area} = $c->req->param('area') if $c->req->param('area');

  $query_key .= 'bid'.$c->req->param('body_id') if $c->req->param('body_id');
  $query_key .= 'from'.$c->req->param('from') if $c->req->param('from');
  $query_key .= 'to'.$c->req->param('to') if $c->req->param('to');
  $query_key .= 'area'.$c->req->param('area') if $c->req->param('area');
  if ( $c->req->param('category') ){
    $c->stash->{category} = $c->req->param('category');
    $query_key .= 'cat'.$c->req->param('category');
  }
  elsif ( $c->req->param('gid') ){
    $c->stash->{gid} = $c->req->param('gid');
    $query_key .= 'gid'.$c->req->param('gid');
  }
  return $query_key;
}

=head2 load_problems
Return conacts by body
=cut
sub load_problems : Private {
  my ( $self, $c ) = @_;

    my $where = $self->load_dates($c, 'confirmed');
    $where->{state} = [ FixMyStreet::DB::Result::Problem->visible_states() ];
    $where->{bodies_str} = $c->stash->{body_id} if $c->stash->{body_id};
    $where->{areas} = { 'like', '%,' . $c->stash->{area} . ',%' } if $c->stash->{area};
    if ( $c->stash->{category} ){
      $where->{category} = $c->stash->{category};
      $c->stash->{api_category} = $c->stash->{category};
    }
    elsif ( $c->stash->{gid} ){
      my @groups = split(/,/, $c->stash->{gid});
      my @cats;
      my $api_groups = $c->forward('get_groups_categories');
      my %api_groups = %{$api_groups};
      foreach ( @groups ) {
        push @cats, @{$api_groups{$_}{categories}} if defined($api_groups{$_});
      }
      $where->{category} = { 'in', \@cats };
      $c->stash->{api_group} = $c->stash->{gid};
    }
    $c->stash->{api_problems} = $c->cobrand->problems->search( \%{$where} );
}

sub get_category_groups: Private {
  my ( $self, $c ) = @_;
  #Get Memcached
  my $mem_api_groups = Memcached::get('category_groups');
  if ( $mem_api_groups ){
    return \%{$mem_api_groups};
  }
  else {
    my @category_groups = $c->model('DB::Contact')->get_groups();
    #my %categories = map { $_->{category} => { total => $_->{c}, fixed => $_->{fixed} } } $categories->all;
    my %api_groups = map {
      $_->category => {
        group_id =>$_->group_id,
        group_name =>$_->contacts_group->group_name,
        group_color =>$_->contacts_group->group_color,
        group_icon =>$_->contacts_group->group_icon,
      }
    } @category_groups;
    Memcached::set('category_groups', \%api_groups, 3600);
    return \%api_groups;
  }
}

sub get_groups_categories : Private {
  my ( $self, $c ) = @_;

  my %where;
  my $gkey = 'group_categories';
  if ( $c->stash->{body_id} ) {
    $where{body_id} = $c->stash->{body_id};
    $gkey .= '_'.$c->stash->{body_id};
  }
  #Get Memcached
  my $mem_api_groups = Memcached::get($gkey);
  if ( $mem_api_groups ){
    return \%{$mem_api_groups};
  }
  else {
    my @category_groups = $c->model('DB::Contact')->search(\%where)->get_groups();
    my %api_groups;
    foreach (@category_groups){
      if (exists $api_groups{$_->group_id}){
        push @{$api_groups{$_->group_id}{categories}}, $_->category;
      }
      else {
        $api_groups{$_->group_id} = {
          group_color => $_->contacts_group->group_color,
          group_name => $_->contacts_group->group_name,
          categories => [$_->category],
        };
      }
    }
    Memcached::set('group_categories', \%api_groups, 3600);
    return \%api_groups;
  }
}

sub get_api_categories : Private {
  my ( $self, $c, $cate ) = @_;
  my $api_groups = $c->forward('get_groups_categories');
  my %api_groups = %{$api_groups};
  if ( $c->stash->{api_group} || $c->stash->{api_category} ){
    my $new_group;
    if ($c->stash->{api_group}) {
      my $gid = $c->stash->{api_group};
      if ($c->stash->{cate}) {
        for my $cat ( @{$api_groups{$gid}{categories}} ) {
          $new_group->{$cat} = {
            group_color => $api_groups{$gid}{group_color},
            group_name => $cat,
            categories => [$cat]
          }
        }
      }
      else {
          $new_group = { $gid => $api_groups{$gid} } ;
      }
    }
    $new_group = { $c->stash->{api_category} => {
      group_color => '',
      group_name => $c->stash->{api_category},
      categories => [$c->stash->{api_category}],
      }
    } if $c->stash->{api_category};
     $api_groups = $new_group;
  }
  else {
    if ( $c->stash->{cate} ){
      $c->stash->{cate} = 0;
      return $c->forward('get_category_groups');
    }
  }
  return $api_groups;
}

sub format_output : Private {
    my ( $self, $c, $hashref ) = @_;
    my $format = $c->stash->{format};
    if ('json' eq $format) {
      $c->res->content_type('application/json; charset=utf-8');
      $c->res->body( encode_json($hashref) );
    } elsif ('xml' eq $format) {
      $c->res->content_type('application/xml; charset=utf-8');
      $c->res->body( XMLout(
        {record => $hashref},
        RootName => 'response',
        noattr => 1,
        xmldecl => '<?xml version="1.0" encoding="UTF-8" ?>')
      );
    } elsif ('csv' eq $format) {
      my $output = get_csv_structure($hashref);
      $c->res->content_type('application/csv; charset=utf-8');
      $c->res->body( $output );
    }
    elsif ('geo_json' eq $format){
      $c->res->content_type('application/json; charset=utf-8');
      $c->res->body( $hashref );
    }
    else {
      $c->stash->{message} = sprintf(_('Invalid format %s specified.'), $format);
      $c->stash->{template} = 'errors/generic.html';
    }
}

sub get_csv_structure : Private {
  my $hashref = shift;
  my $output;

  if (ref($hashref) eq 'ARRAY') {
    my @headers;
    my $first_row = 1;
    for my $row (@{$hashref}) {
      my %row = %{$row};
      my @first;
      my @middle;
      my @last;
      my $multiple = 0;
      foreach my $rkey ( sort keys %row ) {
        if (ref($row{$rkey}) eq 'ARRAY'){
          $multiple = 1;
          my $first_obj = 1;
          foreach my $row_obj (@{$row{$rkey}}) {
            my @obj_keys = sort keys %{$row_obj};
            if ( $first_obj ) {
              push @headers, @obj_keys;
              $first_obj = 0;
            }
            push @middle, join(", ", map { "\"$_\"" } @{$row_obj}{@obj_keys});
          }
        }
        else {
          if ( $first_row) {
            push @headers, $row{$rkey};
          }
          if ($multiple){
            push @last, $row{$rkey};
          }
          else {
            push @first, $row{$rkey};
          }
        }
      }
      if ($first_row){
        $first_row = 0;
        $output = join(", ", map { "\"$_\"" } @headers)."\n";
      }
      if ($multiple) {
        foreach my $obj_val (@middle){
          my @multi;
          push @multi, @first;
          push @multi, $obj_val;
          push @multi, @last;
          $output .= join(", ", map { "\"$_\"" } @multi)."\n";
        }
      }
      else {
        $output .= join(", ", map { "\"$_\"" } @first)."\n";
      }
    }
  }
  else {
    my %href = %{$hashref};
    my @obj_keys = sort keys %{$hashref};
    $output .= join(", ", map { "\"$_\"" } @obj_keys)."\n";
    $output .= join(", ", map { "\"$_\"" } @{$hashref}{@obj_keys})."\n";
  }
  return $output;
}

=head2 reports
Return reports for query
=cut
sub reports : Path('reports') {
  my ( $self, $c ) = @_;

  my $mem_reports = Memcached::get( $c->stash->{query_key}.'reports' );
  if ($mem_reports){
    $c->stash->{api_result} = \@{$mem_reports};
  }
  else {
    my @reports;
    if ( !$c->stash->{api_problems} ) {
      $c->forward('load_problems');
    }
    while ( my $report = $c->stash->{api_problems}->next ){
      my %repo = map { $_ => $report->$_ } qw/id postcode title detail name category latitude longitude external_id confirmed state lastupdate lastupdate_council whensent /;
      $repo{confirmed} = $repo{confirmed}->ymd if defined($repo{confirmed});
      $repo{lastupdate} = $repo{lastupdate}->ymd if defined($repo{lastupdate});
      $repo{lastupdate_council} = $repo{lastupdate_council}->ymd if defined($repo{lastupdate_council});
      $repo{whensent} = $repo{whensent}->ymd if defined($repo{whensent});
      push @reports, \%repo;
    }
    $c->stash->{api_result} = \@reports;
  }
}

sub geo_reports : Path('geo_reports') {
  my ( $self, $c ) = @_;
  #Deceive Memcached
  $c->stash->{query_key} = '.';
  $c->stash->{format} = 'geo_json';
  $c->forward('reports');
  my $reports = $c->stash->{api_result};
  #Load cat groups
  my $groups = $c->forward('get_category_groups');
  my %groups = %{$groups};
  my @fcollection;
  $c->log->debug('GROUPS GEO:'.Dumper($groups));
  foreach my $report (@$reports) {
    #Create point
    my $pt = Geo::JSON::Point->new({
        coordinates => [ $report->{latitude}, $report->{longitude} ],
    });
    my $cat = $report->{category};
    $c->log->debug('GROUPS GEO:'.Dumper($cat));
    #Add properties
    my %pt_prop = (
      id => $report->{id},
      title => $report->{title},
      user => $report->{name},
      category => $cat,
      date => $report->{confirmed},
      state => $report->{state},
      pin_url => '/i/pins/'.$groups{$cat}->{group_icon}.'.png',
      category_url => '/i/category/'.$groups{$cat}->{group_icon}.'.png',
      color => $groups{$cat}->{group_color},
    );
    #Create feature
    my $geo_pin = Geo::JSON::Feature->new({
      geometry   => $pt,
      properties => \%pt_prop,
    });
    #Append feature
    push @fcollection, $geo_pin;
  }
  my $pt = Geo::JSON::FeatureCollection->new({
      features => \@fcollection,
  });
  $c->stash->{api_result} = $pt->to_json;
}

=head2 getTotals
Return totals for query
=cut
sub getTotals : Path('getTotals') {
  my ( $self, $c ) = @_;

  my $totals = Memcached::get( $c->stash->{query_key}.'getTotals' );
  if ( !$totals ){
    my $where = $self->load_dates($c, 'created_date');
    my $users4period = $c->model('DB::User')->count(\%{$where});
    if ( !$c->stash->{api_problems} ) {
      $c->forward('load_problems');
    }
    $totals = {
     'users' => $users4period,
     'reports' => $c->stash->{api_problems}->count()
    };
  }
  $c->stash->{api_result} = \%{$totals}
}

sub reportsByCategoryGroup: Path('reportsByCategoryGroup') {
  my ( $self, $c ) = @_;

  my $mem_groups_total = Memcached::get( $c->stash->{query_key}.'reportsByCategoryGroup' );
  if ( $mem_groups_total ){
    $c->stash->{api_result} = \@{$mem_groups_total};
  }
  else {
    if ( !$c->stash->{api_problems} ) {
      $c->forward('load_problems');
    }
    my %cat_count = $c->stash->{api_problems}->categories_count();
    my %groups_count;
    $c->stash->{cate} = 1;
    my $api_contact_groups = $c->forward( 'get_api_categories' );
    my %api_contact_groups = %{$api_contact_groups};
    foreach my $cat (keys \%cat_count){
      if ( exists $api_contact_groups{$cat} ){
        my $gname = $api_contact_groups{$cat}{group_name};
        if ( exists $groups_count{$gname} ){
          $groups_count{$gname}{'reports'} = $groups_count{$gname}{'reports'} + $cat_count{$cat};
        }
        else {
          $groups_count{$gname} = {
            color => $api_contact_groups{$cat}{group_color},
            reports => $cat_count{$cat},
            groupName => $gname,
          };
        }
      }
      else {
        #else create Other? should be by default in group_id 0
        $c->log->debug('No group for cat: '.$cat);
      }
    }
    my @groups_total = map { $groups_count{$_} } keys %groups_count;
    $c->stash->{api_result} = \@groups_total;
  }
}

sub reportsByState: Path('reportsByState') {
  my ( $self, $c ) = @_;

  my $mem_state_resp = Memcached::get( $c->stash->{query_key}.'reportsByState' );
  if ( $mem_state_resp ){
    $c->stash->{api_result} = \@{$mem_state_resp};
  }
  else {
    if ( !$c->stash->{api_problems} ) {
      $c->forward('load_problems');
    }
    my $state_count = $c->stash->{api_problems}->summary_count();
    my $states = FixMyStreet::DB::Result::Problem->all_states();
    my @state_resp = map { {state => $states->{$_->state}, reports => $_->get_column('state_count')} } $state_count->all;
    $c->stash->{api_result} = \@state_resp;
  }
}

sub reportsEvolution: Path('reportsEvolution'){
  my ( $self, $c ) = @_;

  my $mem_evo_total = Memcached::get( $c->stash->{query_key}.'reportsEvolution' );
  if ( $mem_evo_total ){
    $c->stash->{api_result} = \@{$mem_evo_total};
  }
  else {
    my $parser = DateTime::Format::Strptime->new( pattern => '%Y-%m-%d' );
    #Get groups and count them
    $c->stash->{cate} = 1 if $c->stash->{api_group} || $c->stash->{api_category};
    my $api_groups  = $c->forward('get_api_categories');
    my %api_groups = %{$api_groups};
    my %evo_count;
    if ( !$c->stash->{api_problems} ) {
      $c->forward('load_problems');
    }
    foreach my $gid (keys \%api_groups){
      #Get sub result by group
      my $group_problems = $c->stash->{api_problems}->search({
        category => {-in => \@{$api_groups{$gid}{categories}} }
      });
      if ( $group_problems->count() ) {
        #Get months-year for period
        my $from = $c->stash->{from} ? $c->stash->{from} : $c->cobrand->begining_date();
        my $end_date = $c->stash->{to} ? $c->stash->{to} : DateTime->now;
        my $first_month_day = DateTime->new(
          year  =>  $from->year(),
          month => $from->month(),
          day   => 1,
        );
        my $to = $first_month_day->clone;
        $to->add( months => 1 )->subtract( days => 1 );
        my $date_value = $from->ymd('/');
        my @month_results;
        $evo_count{$api_groups{$gid}{group_name}}{months} = \@month_results;
        while ( $to <= $end_date ){
          my $month_count;
          $month_count = $group_problems->search({
            -AND => [
              created => { '>=', $parser->format_datetime($from) },
              created => { '<=', $parser->format_datetime($to) }
            ],
          });
          push @month_results, { month => $date_value, reports => $month_count->count() };
          $from = $to->clone()->add( days => 1 );
          my $from_last = $from->clone();
          $to = $from_last->add( months => 1 )->subtract( days => 1 );
          $date_value = $from->ymd('/');
        }
        #search for last pice
        my $month_count = $group_problems->search({
          -AND => [
            created => { '>=', $parser->format_datetime($from) },
            created => { '<=', $parser->format_datetime($end_date) }
          ],
        });
        push @month_results, { month => $date_value, reports => $month_count->count() };
        $evo_count{$api_groups{$gid}{group_name}}{groupName} = $api_groups{$gid}{group_name};
        $evo_count{$api_groups{$gid}{group_name}}{color} = $api_groups{$gid}{group_color};
      }
    }
    my @evo_total = map { $evo_count{$_} } keys %evo_count;
    $c->stash->{api_result} = \@evo_total;
  }
}

sub reportsByCategoryState: Path('reportsByCategoryState'){
  my ( $self, $c ) = @_;

  my $mem_groups_total = Memcached::get( $c->stash->{query_key}.'reportsByCategoryState' );
  if ( $mem_groups_total ){
    $c->stash->{api_result} = \@{$mem_groups_total};
  }
  else {
    my $api_groups = $c->forward('get_api_categories');
    my %api_groups = %{$api_groups};
    my %groups_count;
    my $states = FixMyStreet::DB::Result::Problem->all_states();
    if ( !$c->stash->{api_problems} ) {
      $c->forward('load_problems');
    }
    foreach my $gid (keys \%api_groups){
      my $group_count = $c->stash->{api_problems}->search({
        category => {-in => \@{$api_groups{$gid}{categories}} }
      })->summary_count();
      my %state_resp = map { $states->{$_->state} => $_->get_column('state_count') } $group_count->all;
      if (%state_resp) {
        $groups_count{$api_groups{$gid}{group_name}} = {
          color => $api_groups{$gid}{group_color},
          states => \%state_resp,
          groupName => $api_groups{$gid}{group_name}
        }
      }
    }
    my @groups_total = map { $groups_count{$_} } keys %groups_count;
    $c->stash->{api_result} = \@groups_total;
  }
}

sub answerTimeByCategoryGroup: Path('answerTimeByCategoryGroup') {
  my ( $self, $c ) = @_;

  my $mem_groups_total = Memcached::get( $c->stash->{query_key}.'answerTimeByCategoryGroup' );
  if ( $mem_groups_total ){
    $c->stash->{api_result} = \@{$mem_groups_total};
  }
  else {
    if ( !$c->stash->{api_problems} ) {
      $c->forward('load_problems');
    }
    my $completed = $c->stash->{api_problems}->search({
      state => [ FixMyStreet::DB::Result::Problem->fixed_states() ]
    });
    #Get cat_groups to fill details
    $c->stash->{cate} = 1;
    my $api_contact_groups = $c->forward( 'get_api_categories' );
    my %api_contact_groups = %{$api_contact_groups};
    my %groups_average;
    #Sustract completed-confirmed
    while (my $report = $completed->next){
      if ( exists $api_contact_groups{$report->category} ){
        #Get report hours to get solved
        my $gname = $api_contact_groups{$report->category}{group_name};
        if ( exists $groups_average{$gname} ){
          $groups_average{$gname}{'total_seconds'} = $groups_average{$gname}{'total_seconds'} + $report->duration;
          $groups_average{$gname}{'reports_count'} = $groups_average{$gname}{'reports_count'} + 1;
          $groups_average{$gname}{averageTime} = int($groups_average{$gname}{total_seconds}/$groups_average{$gname}{reports_count}/60/60/24);
        }
        else {
          #Get number of reports and total hours
          $groups_average{_($gname)} = {
            groupName => _($gname),
            color => $api_contact_groups{$report->category}{group_color},
            total_seconds => $report->duration,
            reports_count => 1,
            averageTime => int($report->duration/60/60/24),
          };
        }
      }
      else {
        #else create Other? should be by default in group_id 0
        #$c->log->debug('No group for cat: '.$report->category);
      }
    }
    my @groups_total = map { $groups_average{$_} } keys %groups_average;
    $c->stash->{api_result} = \@groups_total;
  }
}

sub answerTimeByState: Path('answerTimeByState') {
  my ( $self, $c ) = @_;
  #Get cat_groups to fill details
  my $mem_groups_total = Memcached::get( $c->stash->{query_key}.'answerTimeByState' );
  if ( $mem_groups_total ){
    $c->stash->{api_result} = \@{$mem_groups_total};
  }
  else {
    my %states_average;
    my $now = DateTime->now;
    my $report;
    my $completed_states = FixMyStreet::DB::Result::Problem->fixed_states();
    my $closed_states = FixMyStreet::DB::Result::Problem->fixed_states();
    my $states = FixMyStreet::DB::Result::Problem->all_states();
    if ( !$c->stash->{api_problems} ) {
      $c->forward('load_problems');
    }
    foreach ( $c->stash->{api_problems}->all ){
      $report = $_;
      my $state = $report->state;
      if ( !$report->confirmed ){
        $c->log->debug('NO HAY CONFIRMED??!!'.$report->id);
      }
      else {
        if ( exists $states_average{$state} ){
          $states_average{$state}{'total_seconds'} = $states_average{$state}{'total_seconds'} + $report->duration;
          $states_average{$state}{'reports_count'} = $states_average{$state}{'reports_count'} + 1;
          $states_average{$state}{averageTime} = int($states_average{$state}{total_seconds}/$states_average{$state}{reports_count}/60/60/24);
        }
        else {
          #Get number of reports and total hours
          $states_average{$report->state} = {
            state => $states->{$report->state},
            total_seconds => $report->duration,
            reports_count => 1,
            averageTime => int($report->duration/60/60/24),
          };
        }
      }
    }
    my @states_total = map { $states_average{$_} } keys %states_average;
    $c->stash->{api_result} = \@states_total;
  }
}

sub groups: Path('groups') {
  my ( $self, $c ) = @_;
  my $res = $c->forward('get_groups_categories');
  $c->stash->{api_result} = \%{$res};
}

sub categories: Path('categories') {
  my ( $self, $c ) = @_;
  my $res = $c->forward('get_category_groups');
  $c->stash->{api_result} = \%{$res};
}

sub bodies: Path('bodies') {
  my ( $self, $c ) = @_;
  my @bodies = $c->model('DB::Body')->all;
  my @body_resp;
  foreach my $body (@bodies) {
    push @body_resp, { $body->id => $body->name };
  }
  $c->stash->{api_result} = \@body_resp;
}

sub areas: Path('all_areas') {
  my ( $self, $c ) = @_;

  my %areas;
  my $all_areas = Memcached::get( 'api_all_areas' );
  if ( $all_areas ){
    %areas = $all_areas;
  }
  else {
    my @bodies = $c->model('DB::Body')->all;
    foreach my $body (@bodies) {
      #Get area information
      $c->log->debug("\nGetting data for body: ".$body->id.":\n".Dumper($body->body_areas) );
      my $area_id = $body->body_areas->first->area_id;
      $c->log->debug("\nGetting data for body: ".$body->id.' in '.$area_id."\n" );
      my $area_childs = mySociety::MaPit::call( 'area', "$area_id/children" );
      my %area_childs = %{$area_childs};
      unless ($area_childs->{error}) {
        foreach ( keys %area_childs ) {
          $areas{$body->id}{$area_childs{$_}->{type_name}}{$_} = $area_childs{$_}->{name};
        }
      }
    }
  }
  $c->stash->{api_result} = \%areas;
}

sub control_reports: Path('control_reports') {
  my ( $self, $c ) = @_;
  #Get array report duration
  my @all_reports = map { {id => $_->id =>, response => $_->duration} } $c->stash->{api_problems}->all;
  #Order array by response time
  my @order_reports = sort { $a->{response} <=> $b->{response} } @all_reports;
  my $medium_key = int(scalar @order_reports/2);
  $medium_key = $medium_key + 1 if ( (scalar @order_reports % 2) == 1 );
  my $medium = $order_reports[$medium_key];
  $c->stash->{api_result} = \@order_reports;
}

sub api_test: Path('apiTest') {
  my ( $self, $c ) = @_;

  my $contact = FixMyStreet::App->model('DB::Contact')->find({ category => 'Residuos fuera del contenedor por capacidad insuficiente', deleted => 0 });
  $c->stash->{api_result} = $contact;
  $c-log->debug(Dumper($contact));
}

__PACKAGE__->meta->make_immutable;

1;
