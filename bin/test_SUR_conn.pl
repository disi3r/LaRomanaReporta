#!/usr/bin/perl


use warnings;
use strict;
use lib '../local/lib/perl5';
use local::lib "../local";
use lib "../commonlib/perllib";
use lib "../perllib";
for ( "../commonlib/perllib", "../perllib" ) {
    $ENV{PERL5LIB} = "$_:$ENV{PERL5LIB}";
}
use URI;
use Moose;
use XML::Simple;
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request::Common qw(POST);
use Data::Dumper;

my $uri = URI->new( 'http://190.64.5.25/open311Montevideo/services.xml');
my $ua = LWP::UserAgent->new;
my $req = HTTP::Request->new(
    GET => $uri->as_string
);
$ua->credentials("190.64.5.25:80", "iprod5tmp02.montevideo.gub.uy:8080", "im9000013", "im9000013");
my $res = $ua->request( $req );
print Dumper($res);
if ( $res->is_success ) {
	print 'SUCCESS';
    #$content = $res->decoded_content;
    #$self->success(1);
} else {
	print 'ERROR';
}