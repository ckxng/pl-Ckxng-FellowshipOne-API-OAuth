use warnings;
use strict;

package Ckxng::FellowshipOne::API::OAuth;

our $VERSION = '1.02';

=head1 NAME

Ckxng::FellowshipOne::API::OAuth

=head1 DESCRIPTION

Handles OAuth communication for the FellowshipOne API

=cut

use Data::Dumper;
use Net::OAuth;
use HTTP::Request::Common;
use MIME::Base64;
use LWP::UserAgent;
use String::Random;
use URI::Escape;
use JSON;

=head1 SUBROUTINES

=head2 new

Initializes the package class.

B<Params>:

=over

=item * B<consumerkey> => 'string'

The second-party OAuth consumer key from FellowshipOne

=item * B<consumersecret> => 'string'

THe second-party OAuth consumer secret key from FellowshipOne

=item * B<portaluser> => 'string'

The username of a FellowshipOne portal user

=item * B<portalpass> => 'string'

The password of a FellosshipOne portal user

=item * B<baseurl> => 'https://api.example.com/api/v1'

A string to prepend to the request URI.  Defaults to an empty string.  If no baseurl is
provided, then the full requesturi must be provided each time.

=item * B<debug> => 0 or 1

Set 'debug' => 1 if debugging output should be sent to STDERR. Defaults to 0.

=back

B<Returns>:

=over

=item * a reference to the instantiated class

=back

B<Example>:

    my $self = __PACKAGE__->new();

=cut
sub new {
  my $class = shift(@_);
  my %params = @_;
  my $self = {
    'debug' => 0,
    'baseurl' => '',
  };

  for(qw( 
      consumerkey consumersecret 
      portaluser portalpass baseurl debug )) {
    if(exists($params{$_})) {
      $self->{$_} = $params{$_};
    }
  }

  bless($self, $class);

  if($self->{'debug'}) {
    print(STDERR "*Ecc12::FellowshipOne::API::OAuth->new()=\n".
        Dumper($self));
  }  

  return($self);
}


=head2 oauth_request_json

Wraps L<oauth_request> and returns a parsed JSON object.

B<Params>:

=over

=item * all parameters passed directly to L<oauth_request>

=back

B<Returns>:

=over

=item * a parsed JSON object

=back

B<Example>:

    $harhref = $self->oauth_request_json("ProtectedResource", undef, $requestdata);

=cut
sub oauth_request_json {
  my $self = shift(@_);
  my $response = $self->oauth_request(@_)->content();
  print STDERR "*oauth_request_json:Dumper($response);\n".Dumper($response) 
      if($self->{'debug'}); 
  return decode_json($self->oauth_request(@_)->content());
}

=head2 generate_nonce

Generate a random string for oauth to use as I<nonce>. I<Nonce> 
is a random value that is unique to each session.  An OAuth request
sends a I<nonce> and a timestamp.  Each I<nonce>/timestamp pair can
only be used once, ever.  This helps to prevent reply attacks on
signatures.

B<Returns>:

=over

=item * a nine-character long random string

=back

B<Example>:

    $nonce = $self->generate_nonce();

=cut
sub generate_nonce {
  my $self = shift(@_);
  my $t = encode_base64($self->{'_randstr'}->randpattern("........."));
  $t =~ s/\s//g;
  return $t;
}

=head2 oauth_request

Sends an OAuth request to the API server and returns the results as a string.
There is no attempt whatsoever to process errors except to die immesiately.
In the event of an error, the use should just retry the request.

B<Params>:

=over

=item B<$name>

The name of the type of request.  to be honest, i'm not completely sure what
this is except that I use "RequestToken" for the requests that log me in
and I use "ProtectedResource" for everything else.  I think it's an OAuth
thing.

=item B<$content>

If this parameter is empty, the request with be an HTTP GET request.  If this
parameter has content, then the request will be an HTTP POST request and this
I$<content> will be the body of that request

=item B<$requestdata>

Hash reference to data needed by the OAuth library to send the request.  The
elements of this hash are defined by L<oauth_initialize_request_data>.

=back

B<Returns>:

=over

=item * OAuth response body as a string

=back

B<Example>:

    $response = $self->oauth_request("RequestToken", $postbody, $requestdata);
    $response = $self->oauth_request("ProtectedResource", undef, $requestdata);

=cut
sub oauth_request {
  my $self = shift(@_);
  my $name = shift(@_);
  my $content = shift(@_);
  my $requestdata = shift(@_);

  print STDERR "*oauth_request(name,content,requestdata)=\n".
      Dumper($name,$content,$requestdata) if($self->{'debug'});

  unless($requestdata->{'request_url'}=~/^http/) {
    if($self->{'baseurl'}=~/^http/) {
      $requestdata->{'request_url'} = $self->{'baseurl'}.$requestdata->{'request_url'};
    }
  }

  unless(exists($self->{'_randstr'}) && exists($self->{'_ua'})) {
    $self->{'_ua'} = LWP::UserAgent->new;
    $self->{'_randstr'} = new String::Random;
  }

  $requestdata->{'nonce'} = $self->generate_nonce();
  $requestdata->{'timestamp'} = time();

  my $request = Net::OAuth->request($name)->new(%{$requestdata});
  $request->sign();

  my $getpost = undef;
  my $response = undef;
  if($requestdata->{'request_method'} eq 'POST') {
    print STDERR "*oauth_request#post\n" if($self->{'debug'});
    $getpost = POST $requestdata->{'request_url'},
      'Authorization' => $request->to_authorization_header(),
      'Content_Type' => 'application/json',
      'Accept' => 'application/json',
      'Content' => $content;
  } elsif($requestdata->{'request_method'} eq 'GET') {
    print STDERR "*oauth_request#get\n" if($self->{'debug'});
    $getpost = GET $requestdata->{'request_url'},
      'Authorization' => $request->to_authorization_header(),
      'Content_Type' => 'application/json',
      'Accept' => 'application/json';
  }

  $response = $self->{'_ua'}->request($getpost);
  print STDERR "*oauth_request:\$response=\n".Dumper($response) if($self->{'debug'});
  die("*!*!* bad HTTP response, do not process errors.\n") 
      unless($response->{'_rc'} eq '200');
  return $response;
}

=head2 oauth_initialize_request_data

Create a hash containing request data and return it.

B<Returns>:

=over

=item * a reference to a newly created hash

=back

B<Example>:

    $requestdata = $self->oauth_initialize_request_data();
    for( qw(
          consumer_key
          consumer_secret
          signature_method
          nonce
          request_url
          request_method
          timestamp
          token
          token_secret
          callback
          extra_params
            ) ) {
      printf("%s => %s\n", $_, $requestdata->{$_});
    }
    $response = $self->oauth_request("ProtectedResource", 
                                       undef, $requestdata);

=cut
sub oauth_initialize_request_data {
  my $self = shift(@_);

  my $requestdata = {
    consumer_key => $self->{'consumerkey'},
    consumer_secret => $self->{'consumersecret'},
    signature_method => 'HMAC-SHA1',
    nonce => undef,
    request_url => undef,
    request_method => undef,
    timestamp => undef,
    token => undef,
    token_secret => undef,
    callback => undef,
    extra_params => {
    }
  };
  print STDERR "*oauth_initialize_request_data:return=\n".Dumper($requestdata) 
      if($self->{'debug'});
  return $requestdata;
}

=head2 oauth_login

Login to the FellowshipOne API.  A I<token> and I<token_secret> will be 
added to I<$requestdata>.  This will allow future requests to access 
protected resources.

B<Params>:

=over

=item * B<$requestdata>

=back

B<Returns>:

=over

=item * a reference to I<$requestdata>

=back

B<Example>:

    $requestdata = $self->oauth_login($requestdata);

=cut
sub oauth_login {
  my $self = shift(@_);
  my $requestdata = shift(@_);

  print STDERR "*oauth_login\n" if($self->{'debug'});

  print STDERR "*oauth_login\n" if($self->{'debug'});

  my $unencodedlogin = sprintf('%s %s', $self->{'portaluser'}, $self->{'portalpass'});
  my $loginstring = encode_base64($unencodedlogin);
  $loginstring =~ s/\s//g;
  print STDERR "*oauth_login:\$unencodedlogin=$unencodedlogin\n" if($self->{'debug'});
  print STDERR "*oauth_login:\$loginstring=$loginstring\n" if($self->{'debug'});

  # request acess token with username and password
  $requestdata->{'request_method'} = 'POST';
  $requestdata->{'request_url'} = '/v1/PortalUser/AccessToken';
  my $response = $self->oauth_request("RequestToken",
      uri_escape("$loginstring"), $requestdata);

  # save access token
  if ($response->is_success) {
    my $response = Net::OAuth->response('RequestToken')->from_post_body($response->content);
    $requestdata->{'token'} = $response->token;
    $requestdata->{'token_secret'} = $response->token_secret;
  } else {
    return;
  }
  return $requestdata;
}

=head1 CHANGES

=over

=item * 1.00

Initial version.

=item * 1.01

Update to use lib ./locallib/

=item * 1.02

Split into Ckxng::FellowshipOne::API::OAuth.  Remove lib ./locallib/.
No longer using globals for configuration, passing that data by name to new.

=back

=head1 COPYRIGHT

Copyright 2011 Cameron C. King. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are 
met:
    
1. Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   
2. Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.
    
THIS SOFTWARE IS PROVIDED BY CAMERON C. KING ''AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. 
IN NO EVENT SHALL CAMERON C. KING OR CONTRIBUTORS BE LIABLE FOR ANY 
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES 
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR 
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY 
OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF 
SUCH DAMAGE.
    

=head1 AUTHOR

Cameron C. King <http://cameronking.me>

=cut

1;

