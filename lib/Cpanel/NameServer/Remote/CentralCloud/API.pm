package Cpanel::NameServer::Remote::CentralCloud::API;

# A wrapper around HTTP::Tiny for use with the PowerDNS API
# Used by CentralCloud plugin to communicate with PowerDNS

use strict;
use warnings;

use Cpanel::JSON::XS;
use HTTP::Tiny;
use Cpanel::Encoder::URI;

our @ISA = qw(Exporter);
our @EXPORT = qw(pdns_url);

our $VERSION = '0.1.0';

# Build an HTTP::Tiny-like client that's authenticated to the PowerDNS API.
sub new {
    my ($class, %args) = @_;

    # Validate input
    if (!defined $args{'api_url'}) {
        die("api_url not defined\n");
    }

    if (!defined $args{'api_key'}) {
        die("api_key not defined\n");
    }

    if (!defined $args{'timeout'}) {
        $args{'timeout'} = 60;
    }

    if (!defined $args{'debug'}) {
        $args{'debug'} = 0;
    }

    # Store the API URL for use in request URLs
    my $api_url = $args{'api_url'};
    $api_url =~ s{/$}{};  # Remove trailing slash if present
    
    # Build the object
    my $self = {
        'debug' => $args{'debug'} ? 1 : 0,
        'api_url' => $api_url,
    };

    # Add an authenticated HTTP client to the object
    $self->{'http_client'} = HTTP::Tiny->new(
        'agent'           => sprintf('%s/%s', __PACKAGE__, $VERSION),
        'verify_SSL'      => 1,
        'keep_alive'      => 1,
        'timeout'         => $args{'timeout'},
        'default_headers' => {
            'Accept'        => 'application/json',
            'Content-Type'  => 'application/json',
            'X-API-Key'     => $args{'api_key'},
        },
    );

    bless $self, $class;
    return $self;
}

# Make a request of the PowerDNS API
sub request {
    my ($self, $method, $endpoint, $args) = @_;

    if (!$args) {
        $args = {};
    }

    my $url = $self->{'api_url'} . $endpoint;

    $self->_debug('Making a PowerDNS API call');
    $self->_debug(sprintf('Method: %s', $method));
    $self->_debug(sprintf('URL: %s', $url));
    $self->_debug('Arguments', $args);

    my $response = $self->{'http_client'}->request($method, $url, $args);

    $self->_debug('Response', $response);

    # PowerDNS API response should be JSON or empty
    if ($response->{'headers'}->{'content-type'} && 
        $response->{'headers'}->{'content-type'} eq 'application/json' &&
        $response->{'content'}) {
        
        # JSON decode the response body
        $response->{'decoded_content'} = eval {
            decode_json($response->{'content'});
        };

        if ($@ ne '') {
            $self->_debug('Unable to JSON decode PowerDNS API response');
            die("unable to decode PowerDNS API response\n");
        }
    }
    else {
        $response->{'decoded_content'} = $response->{'content'};
    }

    return $response;
}

# Print a debug message to the API object's error file
sub _debug {
    my ($self, $message, $data) = @_;

    # Only debug when configured to
    if (!$self->{debug}) {
        return $self;
    }

    warn "debug: " . $message . "\n";

    if ($data) {
        use Data::Dumper;
        warn Dumper($data) . "\n";
    }

    return $self;
}

# Helper to build PowerDNS URL with query parameters
sub pdns_url {
    my ($endpoint, $query) = @_;
    my $query_string = '';

    if ($query && ref $query eq 'HASH') {
        my @query_string_parts = ();

        while (my ($key, $value) = each %{$query}) {
            push @query_string_parts, sprintf('%s=%s', 
                Cpanel::Encoder::URI::uri_encode_str($key), 
                Cpanel::Encoder::URI::uri_encode_str($value));
        }

        $query_string = sprintf('?%s', join('&', @query_string_parts));
    }

    return $endpoint . $query_string;
}

1;