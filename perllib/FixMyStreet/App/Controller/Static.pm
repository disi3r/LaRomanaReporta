package FixMyStreet::App::Controller::Static;
use Moose;
use namespace::autoclean;
use Data::Dumper;
use FixMyStreet::App;
use JSON;
use utf8;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

FixMyStreet::App::Controller::Static - Catalyst Controller

=head1 DESCRIPTION

Static pages Catalyst Controller. FAQ does some smarts to choose the correct
template depending on language, will need extending at some point.

=head1 METHODS

=cut

sub about : Global : Args(0) {
    my ( $self, $c ) = @_;

    my $lang_code = $c->stash->{lang_code};
    my $template  = "static/about-$lang_code.html";
    $c->stash->{template} = $template;
}

sub privacy : Global : Args(0) {
    my ( $self, $c ) = @_;
}

sub faq : Global : Args(0) {
    my ( $self, $c ) = @_;

    # There should be a faq template for each language in a cobrand or default.
    # This is because putting the FAQ translations into the PO files is
    # overkill.
    
    # We rely on the list of languages for the site being restricted so that there
    # will be a faq template for that language/cobrand combo.
        
    my $lang_code = $c->stash->{lang_code};
    my $template  = "faq/faq-$lang_code.html";
    $c->stash->{template} = $template;
}

sub fun : Global : Args(0) {
    my ( $self, $c ) = @_;
    # don't need to do anything here - should just pass through.
}

sub posters : Global : Args(0) {
    my ( $self, $c ) = @_;
}

sub iphone : Global : Args(0) {
    my ( $self, $c ) = @_;
}

sub stats : Global : Args(0) {
    my ( $self, $c ) = @_;

    my ( $start_date, $end_date, @errors );
    my $parser = DateTime::Format::Strptime->new( pattern => '%Y-%m-%d' );
    my $now_start = DateTime->now(formatter => $parser);
    my $now = DateTime->now(formatter => $parser);

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
        $start_date = '2014-08-01';
    }
    else{
        if (!$c->req->param('end_date')){
            $end_date = $now;
        }
        else{
            $end_date = $parser->parse_datetime( $c->req->param('end_date') ) ;
        }

        if (!$c->req->param('start_date')){
            $start_date = '2014-08-01';
        }
        else{
            $start_date = $parser->parse_datetime( $c->req->param('start_date') );
        }
    }
    $c->log->debug($end_date.'<--END TIME START-->'.$start_date);
    push @errors, _('Invalid start date') unless defined $start_date;
    push @errors, _('Invalid end date') unless defined $end_date;

    $c->stash->{errors} = \@errors;
    $c->stash->{start_date} = $start_date;
    $c->stash->{end_date} = $end_date;

    return 1 if @errors;

    #Cache Groups if not in memcached

    #Get contact and groups for render properly
    my @contacts                #
      = $c                      #
      ->model('DB::Contact')    #
      ->not_deleted             #
      ->search(
            {
                -AND => [
                'deleted' => { '=', 'f'},
                'non_public' => { '=', 'f' },
                ]
            },
            {select => ['category', 'group_id']}
        )
      ->all;
    @contacts = map { { $_->get_columns } } @contacts;
    my @contacts_group                #
      = $c                            #
      ->model('DB::ContactsGroup')    #
      ->search()
      ->all;
    @contacts_group = map { { $_->get_columns } } @contacts_group;
    my $problem_by_group = {
        total => 0,
        fixed => 0,
        in_progress => 0,
        confirmed => 0
    };
    for my $contact (@contacts){
        for my $contact_group (@contacts_group){
            if ( exists $contact->{group_id} and $contact->{group_id} eq $contact_group->{group_id} ){
                unless (exists $problem_by_group->{$contact->{group_id}}) {
                    $problem_by_group->{$contact->{group_id}}{name} = utf8::encode($contact_group->{group_name});
                    $problem_by_group->{$contact->{group_id}}{total} = 0;
                    $problem_by_group->{$contact->{group_id}}{fixed} = 0;
                    $problem_by_group->{$contact->{group_id}}{in_progress} = 0;
                    $problem_by_group->{$contact->{group_id}}{confirmed} = 0;
                    $problem_by_group->{$contact->{group_id}}{evolution} = [0];
                }
                $problem_by_group->{$contact->{group_id}}{$contact->{category}}{name} = utf8::encode($contact->{category});
                $problem_by_group->{$contact->{group_id}}{$contact->{category}}{total} = 0;
                $problem_by_group->{$contact->{group_id}}{$contact->{category}}{fixed} = 0;
                $problem_by_group->{$contact->{group_id}}{$contact->{category}}{in_progress} = 0;
                $problem_by_group->{$contact->{group_id}}{$contact->{category}}{confirmed} = 0;
                $problem_by_group->{$contact->{group_id}}{$contact->{category}}{evolution}{fixed} = [0];
                $problem_by_group->{$contact->{group_id}}{$contact->{category}}{evolution}{in_progress} = [0];
                $problem_by_group->{$contact->{group_id}}{$contact->{category}}{evolution}{confirmed} = [0];
            }
        }
    }

    my $one_day = DateTime::Duration->new( days => 1 );

    my %select = (
            state => [ FixMyStreet::DB::Result::Problem->visible_states() ],
            select => [ 
                'id', 'latitude', 'longitude', 'category', 'external_id', 
                'created', 'confirmed', 'state', 'whensent', 'lastupdate' ],
            order_by => [ 'confirmed, state' ],
    );

    my @problems = $c->model('DB::Problem')->search(
        {
            -AND => [
                'confirmed' => { '>=', $start_date },
                'confirmed' => { '<=', $end_date + $one_day },
                'state'     => { '!=', 'hidden' }
            ],
        },
        \%select
    );
    @problems = map { { $_->get_columns } } @problems;
    my $problem_csv = '"id","latitude","longitude","category","external_id","created","confirmed","whensent","lastupdate","state"\r\n';
    my $first = 1;
    my @months;
    my @evolution_totals;
    my $month_last;
    my $problem;

    for my $problem (@problems){
        foreach my $group_id (keys $problem_by_group){
            if ( ref($problem_by_group->{$group_id}) eq 'HASH' and exists $problem_by_group->{$group_id}->{$problem->{category}} ){
                $problem_by_group->{$group_id}->{$problem->{category}}{total}++;
                $problem_by_group->{$group_id}{total}++;
                #Evolution
                my @confirmed_date  = split('-', $problem->{confirmed});
                my $month = $confirmed_date[0].'/'.$confirmed_date[1];
                if ( $month eq $month_last ){
                    #add one to the last value of the array
                    $problem_by_group->{$group_id}{evolution}->[-1]++;
                }
                else{
                    #create category
                    push @months, $month;
                    if ($first){
                        $first = 0;
                    }
                    else{
                        #Generate added values for new month 
                        foreach my $key (keys $problem_by_group){
                            if ( ref($problem_by_group->{$key}) eq 'HASH' ){
                                push $problem_by_group->{$key}{evolution}, $problem_by_group->{$key}{evolution}->[-1];
                                foreach my $g_keys (keys $problem_by_group->{$key}){
                                    if ( ref($problem_by_group->{$key}{$g_keys}) eq 'HASH'){
                                        push $problem_by_group->{$key}{$g_keys}{evolution}{fixed}, $problem_by_group->{$key}{$g_keys}{evolution}{fixed}->[-1];
                                        push $problem_by_group->{$key}{$g_keys}{evolution}{in_progress}, $problem_by_group->{$key}{$g_keys}{evolution}{in_progress}->[-1];
                                        push $problem_by_group->{$key}{$g_keys}{evolution}{confirmed}, $problem_by_group->{$key}{$g_keys}{evolution}{confirmed}->[-1];
                                    }
                                }
                            }
                        }
                    }
                    #add one to evolution_totals
                    $problem_by_group->{$group_id}{evolution}->[-1]++;
                    $month_last = $month;
                }
                #By State
                if ( $problem->{state} =~ /fixed/ ){
                    $problem_by_group->{fixed}++;
                    $problem_by_group->{$group_id}{fixed}++;
                    $problem_by_group->{$group_id}->{$problem->{category}}{fixed}++;
                    if ( $month eq $month_last ){
                        $problem_by_group->{$group_id}->{$problem->{category}}{evolution}{fixed}->[-1]++;
                    }
                    else{
                        push $problem_by_group->{$group_id}->{$problem->{category}}{evolution}{fixed}, $problem_by_group->{$group_id}->{$problem->{category}}{evolution}{fixed}->[-1];
                    }
                }
                elsif ($problem->{state} eq 'in progress'){
                    $problem_by_group->{in_progress}++;
                    $problem_by_group->{$group_id}{in_progress}++;
                    $problem_by_group->{$group_id}->{$problem->{category}}{in_progress}++;
                    if ( $month eq $month_last ){
                        $problem_by_group->{$group_id}->{$problem->{category}}{evolution}{in_progress}->[-1]++;
                    }
                    else{
                        push $problem_by_group->{$group_id}->{$problem->{category}}{evolution}{in_progress}, $problem_by_group->{$group_id}->{$problem->{category}}{evolution}{in_progress}->[-1];
                    }
                }
                else{
                    $problem_by_group->{confirmed}++;
                    $problem_by_group->{$group_id}{confirmed}++;
                    $problem_by_group->{$group_id}->{$problem->{category}}{confirmed}++;
                    if ( $month eq $month_last ){
                        $problem_by_group->{$group_id}->{$problem->{category}}{evolution}{confirmed}->[-1]++;
                    }
                    else{
                        push $problem_by_group->{$group_id}->{$problem->{category}}{evolution}{confirmed}, $problem_by_group->{$group_id}->{$problem->{category}}{evolution}{confirmed}->[-1]
                    }
                }
                $problem_by_group->{total}++;
                last;
            }
        }
        $problem_by_group->{users} = $c->cobrand->problems->unique_users;

        $problem_csv .= $problem->{id}.',"'.
            $problem->{latitude}.'","'.
            $problem->{longitude}.'","'.
            $problem->{category}.'","'.
            $problem->{external_id}.'","'.
            $problem->{created}.'","'.
            $problem->{confirmed}.'","'.
            $problem->{whensent}.'","'.
            $problem->{lastupdate}.'","'.
            $problem->{state}.'"\r\n';
    }

    my @start_date_arr = split('T', $start_date);
    my $start_date_solo = $start_date_arr[0];
    my @end_date_arr = split('T', $end_date);
    my $end_date_solo = $end_date_arr[0];

    $c->stash->{start_date_solo} = $start_date_solo;
    $c->stash->{end_date_solo} = $end_date_solo;

    my $problem_json = encode_json($problem_by_group);
    my $months_json = encode_json(\@months);
    $c->stash->{months_json} = $months_json;
    $c->stash->{stats_json} = $problem_json;
    $c->stash->{problem_csv} = "'".$problem_csv."'";

    return 1;
}

__PACKAGE__->meta->make_immutable;

1;

