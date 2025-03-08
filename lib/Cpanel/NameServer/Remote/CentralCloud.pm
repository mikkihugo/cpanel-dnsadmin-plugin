package Cpanel::NameServer::Remote::PowerDNS;

# An implementation of the cPanel dns clustering interface for PowerDNS
# Adapted from the StackPath DNS plugin

use strict;
use warnings;

use Cpanel::DnsUtils::RR         ();
use Cpanel::Encoder::URI         ();
use Cpanel::JSON                 ();
use Cpanel::JSON::XS             qw(encode_json);
use Cpanel::Logger               ();
use Cpanel::NameServer::Remote::PowerDNS::API;
use cPanel::PublicAPI            ();
use Cpanel::SocketIP             ();
use Cpanel::StringFunc::Match    ();
use Cpanel::ZoneFile             ();
use Cpanel::ZoneFile::Versioning ();
use HTTP::Date                   ();
use List::Util                   qw(min);
use List::MoreUtils              qw(any natatime none uniq);
use Time::Local                  qw(timegm);

use parent 'Cpanel::NameServer::Remote';

our $VERSION = '0.1.0';

# A cache of remote PowerDNS zones
my $local_cache = [];

# Record types supported by PowerDNS
my @SUPPORTED_RECORD_TYPES = ('A', 'AAAA', 'CNAME', 'MX', 'NS', 'PTR', 'SOA', 'SRV', 'TXT', 'CAA');

# Record types that need periods appended to their values
my @RECORDS_NEEDING_TRAILING_PERIODS = ('CNAME', 'MX', 'NS', 'PTR');

# Field mappings for different record types
my $RECORD_DATA_FIELDS = {
    'A'     => 'address',
    'AAAA'  => 'address',
    'CNAME' => 'cname',
    'MX'    => 'exchange',
    'NS'    => 'nsdname',
    'PTR'   => 'ptrdname',
    'SOA'   => 'rname',
    'SRV'   => 'target',
    'TXT'   => 'txtdata',
    'CAA'   => 'data',
};

# Build a new PowerDNS DNS module
sub new {
    my ($class, %args) = @_;
    my $debug = $args{'debug'} || 0;
    my $self = {
        'name'            => $args{'host'},
        'update_type'     => $args{'update_type'},
        'queue_callback'  => $args{'queue_callback'},
        'output_callback' => $args{'output_callback'},
        'server_id'       => $args{'server_id'} || 'localhost',
        'debug'           => $debug,
        'http_client'     => Cpanel::NameServer::Remote::PowerDNS::API->new(
            'api_url'     => $args{'api_url'},
            'api_key'     => $args{'api_key'},
            'timeout'     => $args{'remote_timeout'},
            'debug'       => $debug,
        ),
    };

    bless $self, $class;
    $local_cache = $self->_cache_zones();

    return $self;
}

# Add a zone to the PowerDNS server
sub addzoneconf {
    my ($self, $request_id, $input, $raw_input) = @_;
    chomp($input->{'zone'});

    # Format zone name properly (with trailing dot)
    my $zone_name = $input->{'zone'};
    $zone_name .= '.' unless $zone_name =~ /\.$/;

    # Create a minimal SOA record for the new zone
    my $ns_hostname = 'ns1.' . $zone_name;
    my $admin_email = 'hostmaster.' . $zone_name;
    my $soa_content = "$ns_hostname $admin_email " . time() . " 10800 3600 604800 3600";

    # Prepare the zone request body
    my $request_body = {
        'name' => $zone_name,
        'kind' => 'Native',
        'dnssec' => JSON::false,
        'soa_edit_api' => 'INCEPTION-INCREMENT',
        'rrsets' => [
            {
                'name' => $zone_name,
                'type' => 'SOA',
                'ttl' => 3600,
                'records' => [
                    {
                        'content' => $soa_content,
                        'disabled' => JSON::false,
                    }
                ]
            },
            {
                'name' => $zone_name,
                'type' => 'NS',
                'ttl' => 3600,
                'records' => [
                    {
                        'content' => $ns_hostname,
                        'disabled' => JSON::false,
                    }
                ]
            }
        ]
    };

    # Create the zone in PowerDNS
    my $res = $self->{'http_client'}->request(
        'POST',
        pdns_url(sprintf('/api/v1/servers/%s/zones', $self->{'server_id'})),
        {'content' => encode_json($request_body)}
    );

    if (!$res->{'success'}) {
        return _fail(
            sprintf('Unable to save zone "%s": %s: %s', $input->{'zone'}, $res->{'status'}, $res->{'content'})
        );
    }

    # Add the zone to the local cache
    my $zone = $res->{'decoded_content'};
    push @{$local_cache}, $zone;

    $self->output(sprintf("Added zone \"%s\" to %s\n", $input->{'zone'}, $self->{'name'}));
    return _success();
}

# Get all zone files from PowerDNS
sub getallzones {
    my ($self, $request_id, $input, $raw_input) = @_;

    foreach my $zone (@{$local_cache}) {
        $self->output(sprintf(
            'cpdnszone-%s=%s&',
            Cpanel::Encoder::URI::uri_encode_str($zone->{'name'}),
            Cpanel::Encoder::URI::uri_encode_str(_build_zone_file($zone))
        ));
    }
}

# Get the IP addresses of the nameservers
sub getips {
    my ($self, $request_id, $input, $raw_input) = @_;
    my @ips;

    foreach my $name_server (@{$self->_get_name_servers()}) {
        push @ips, Cpanel::SocketIP::_resolveIpAddress($name_server);
    }

    $self->output(join("\n", @ips) . "\n");
    return _success();
}

# Get the nameservers path
sub getpath {
    my ($self, $request_id, $input, $raw_input) = @_;

    $self->output(join("\n", @{$self->_get_name_servers()}) . "\n");
    return _success();
}

# Get a single zone
sub getzone {
    my ($self, $request_id, $input, $raw_input) = @_;
    chomp($input->{'zone'});

    my @zones = _find_zone($input->{'zone'});
    my $size = scalar @zones;

    if ($size > 1) {
        return _fail(sprintf('more than one match found for zone "%s"', $input->{'zone'}));
    }

    if ($size == 0) {
        return _fail(sprintf('zone "%s" not found', $input->{'zone'}));
    }

    $self->output(_build_zone_file($zones[0]));
    return _success();
}

# List all zones
sub getzonelist {
    my ($self, $request_id, $input, $raw_input) = @_;
    my @zones = map { $_->{'name'} =~ s/\.$//r } @{$local_cache};

    $self->output(join("\n", @zones) . "\n");
    return _success();
}

# Get multiple zones
sub getzones {
    my ($self, $request_id, $input, $raw_input) = @_;
    chomp($input->{'zone'});

    if (defined $input->{'zones'}) {
        chomp($input->{'zones'});
    }

    my @zones;
    my @search_for = split(/\,/, $input->{'zones'} || $input->{'zone'});

    # Look for zones in the cache
    foreach my $zone_name (@search_for) {
        chomp $zone_name;

        my @found_zones = _find_zone($zone_name);

        # Only render the zone if it's found in the cache
        if ((scalar @found_zones) == 1) {
            push @zones, $found_zones[0];
        }
    }

    # Render zones to BIND-compatible zone files
    foreach my $zone (@zones) {
        $self->output(sprintf(
            'cpdnszone-%s=%s&',
            Cpanel::Encoder::URI::uri_encode_str($zone->{'name'} =~ s/\.$//r),
            Cpanel::Encoder::URI::uri_encode_str(_build_zone_file($zone))
        ));
    }

    return _success();
}

# Add a zone and save its contents in one operation
sub quickzoneadd {
    my ($self, $request_id, $input, $raw_input) = @_;

    return $self->savezone(sprintf('%s_1', $request_id), $input, $raw_input);
}

# Remove a zone
sub removezone {
    my ($self, $request_id, $input, $raw_input) = @_;
    chomp($input->{'zone'});

    # Make sure the zone exists
    my @zones = _find_zone($input->{'zone'});
    my $size = scalar @zones;

    if ($size > 1) {
        return _fail(sprintf('more than one match found for zone "%s"', $input->{'zone'}));
    }

    if ($size == 0) {
        return _fail(sprintf('zone "%s" not found', $input->{'zone'}));
    }

    # Remove the zone from PowerDNS
    my $zone_id = $zones[0]->{'id'};
    my $res = $self->{'http_client'}->request(
        'DELETE',
        pdns_url(sprintf('/api/v1/servers/%s/zones/%s', $self->{'server_id'}, $zone_id))
    );

    if (!$res->{'success'}) {
        return _fail(
            sprintf('Unable to remove zone "%s": %s: %s', $input->{'zone'}, $res->{'status'}, $res->{'content'})
        );
    }

    # Remove the zone from the local cache
    my @new_cache = grep { $_->{'id'} ne $zone_id } @{$local_cache};
    $local_cache = \@new_cache;

    $self->output(sprintf("%s => deleted from %s\n", $input->{'zone'}, $self->{'name'}));
    return _success();
}

# Remove multiple zones
sub removezones {
    my ($self, $request_id, $input, $raw_input) = @_;
    chomp($input->{'zone'});

    if (defined $input->{'zones'}) {
        chomp($input->{'zones'});
    }

    my @zones;
    my @search_for = split(/\,/, $input->{'zones'} || $input->{'zone'});

    # Look for zones in the cache
    foreach my $zone_name (@search_for) {
        chomp $zone_name;

        my @found_zones = _find_zone($zone_name);

        if ((scalar @found_zones) == 1) {
            push @zones, $found_zones[0];
        }
    }

    # Remove each zone and fail out on the first error
    my $count = 0;
    foreach my $zone (@zones) {
        my ($code, $message) = $self->removezone(
            sprintf('%s_%s', $request_id, $count), 
            {'zone' => $zone->{'name'} =~ s/\.$//r}, 
            {}
        );

        if ($code != $Cpanel::NameServer::Constants::SUCCESS) {
            return _fail($message);
        }

        $count++;
    }

    return _success();
}

# Save zone contents
sub savezone {
    my ($self, $request_id, $input, $raw_input) = @_;
    chomp($input->{'zone'});

    # Format zone name properly (with trailing dot for PowerDNS)
    my $zone_name = $input->{'zone'};
    my $pdns_zone_name = $zone_name . '.';
    $pdns_zone_name =~ s/\.\.$/\./; # Avoid double dots

    # Check if the zone exists
    my @zones = _find_zone($zone_name);
    my $size = scalar @zones;
    my $zone_exists = $size == 1;

    if ($size > 1) {
        return _fail(sprintf('more than one match found for zone "%s"', $input->{'zone'}));
    }

    # Parse the zone file from cPanel
    my $local_zone = eval {
        Cpanel::ZoneFile->new('domain' => $input->{'zone'}, 'text' => $input->{'zonedata'});
    };

    if (!$local_zone || $local_zone->{'error'}) {
        my $message = sprintf(
            "%s: Unable to save the zone %s on the remote server [%s] (Could not parse zonefile%s)",
            __PACKAGE__,
            $input->{'zone'},
            $self->{'name'},
            $local_zone ? sprintf(' - %s', $local_zone->{'error'}) : ''
        );

        return _fail($message, $Cpanel::NameServer::Constants::ERROR_GENERIC_LOGGED);
    }

    # Add the zone if needed before updating records
    if (!$zone_exists) {
        my ($code, $message) = $self->addzoneconf($request_id, {'zone' => $input->{'zone'}}, {});

        if ($code != $Cpanel::NameServer::Constants::SUCCESS) {
            return _fail($message, $code)
        }

        @zones = _find_zone($zone_name);
    }

    my $zone = $zones[0];
    my $zone_id = $zone->{'id'};

    # Convert zonefile records to PowerDNS format
    my @rrsets = ();
    
    # Group records by name and type as PowerDNS uses RRsets
    my %grouped_records;
    foreach my $record (@{$local_zone->{'dnszone'}}) {
        # Skip unsupported record types
        if (none { $record->{'type'} eq $_ } @SUPPORTED_RECORD_TYPES) {
            next;
        }
        
        my $record_name = $record->{'name'};
        # Ensure record name ends with a period for PowerDNS
        if ($record_name !~ /\.$/) {
            if ($record_name eq '@') {
                $record_name = $pdns_zone_name;
            }
            else {
                $record_name = "$record_name.$pdns_zone_name";
            }
        }
        
        my $key = "$record_name:" . $record->{'type'};
        $grouped_records{$key} ||= {
            'name' => $record_name,
            'type' => $record->{'type'},
            'ttl' => $record->{'ttl'},
            'records' => []
        };
        
        # Convert record content based on type
        my $content = _get_record_content($record, $pdns_zone_name);
        
        push @{$grouped_records{$key}->{'records'}}, {
            'content' => $content,
            'disabled' => JSON::false
        };
    }
    
    # Convert the grouped records hash to an array of RRsets
    foreach my $key (keys %grouped_records) {
        push @rrsets, $grouped_records{$key};
    }
    
    # Update the zone in PowerDNS
    foreach my $rrset (@rrsets) {
        my $request_body = {
            'rrsets' => [
                {
                    'name' => $rrset->{'name'},
                    'type' => $rrset->{'type'},
                    'ttl' => $rrset->{'ttl'},
                    'changetype' => 'REPLACE',
                    'records' => $rrset->{'records'}
                }
            ]
        };
        
        my $res = $self->{'http_client'}->request(
            'PATCH',
            pdns_url(sprintf('/api/v1/servers/%s/zones/%s', $self->{'server_id'}, $zone_id)),
            {'content' => encode_json($request_body)}
        );

        if (!$res->{'success'}) {
            return _fail(
                sprintf('Unable to update zone "%s": %s: %s', 
                        $input->{'zone'}, $res->{'status'}, $res->{'content'})
            );
        }
    }
    
    # Update the local cache
    $self->_refresh_zone_in_cache($zone_id);

    $self->output(sprintf("Saved zone \"%s\" to %s\n", $input->{'zone'}, $self->{'name'}));
    return _success();
}

# Synchronize multiple zones
sub synczones {
    my ($self, $request_id, $input, $raw_input) = @_;

    # Remove the unique id value from input to save memory.
    $raw_input =~ s/^dnsuniqid=[^\&]+\&//;
    $raw_input =~ s/\&dnsuniqid=[^\&]+//g;

    # Build a list of zone names and contents
    my %zones = map { (split(/=/, $_, 2))[0, 1] } split(/\&/, $raw_input);
    delete @zones{grep(!/^cpdnszone-/, keys %zones)};

    # Save each zone in the input
    my $i = 0;
    foreach my $zone_name (keys %zones) {
        my $zone = $zones{$zone_name};
        $zone_name =~ s/^cpdnszone-//g;

        my ($code, $message) = $self->savezone(
            sprintf('%s_%s', $request_id, ++$i),
            {
                'zone' => Cpanel::Encoder::URI::uri_decode_str($zone_name),
                'zonedata' => Cpanel::Encoder::URI::uri_decode_str($zone),
            }
        );

        if ($code != $Cpanel::NameServer::Constants::SUCCESS) {
            return _fail($message, $code)
        }
    }

    return _success();
}

# Return module version
sub version {
    my ($self, $request_id, $input, $raw_input) = @_;
    return $VERSION;
}

# Check if a zone exists
sub zoneexists {
    my ($self, $request_id, $input, $raw_input) = @_;
    chomp($input->{'zone'});

    my @found_zones = _find_zone($input->{'zone'});
    my $size = scalar @found_zones;

    if ($size > 1) {
        return _fail(sprintf('more than one match found for zone "%s"', $input->{'zone'}));
    }

    $self->output($size == 0 ? '0' : '1');
    return _success();
}

# Clean DNS zones (no-op for PowerDNS)
sub cleandns {
    my ($self, $request_id, $input, $raw_input) = @_;

    $self->output(sprintf("No cleanup needed on %s\n", $self->{'name'}));
    return _success();
}

# Reload PowerDNS
sub reloadbind {
    my ($self, $request_id, $input, $raw_input) = @_;

    # PowerDNS API doesn't require a reload after changes
    $self->output(sprintf("No reload needed on %s\n", $self->{'name'}));
    return _success();
}

# Reload specific zones (no-op for PowerDNS)
sub reloadzones {
    my ($self, $request_id, $input, $raw_input) = @_;

    $self->output(sprintf("No reload needed on %s\n", $self->{'name'}));
    return _success();
}

# Reconfigure PowerDNS (no-op)
sub reconfigbind {
    my ($self, $request_id, $input, $raw_input) = @_;

    $self->output(sprintf("No reconfig needed on %s\n", $self->{'name'}));
    return _success();
}

# Success response helper
sub _success {
    my ($message) = @_;

    if (!$message) {
        $message = 'OK';
    }

    return ($Cpanel::NameServer::Constants::SUCCESS, $message);
}

# Failure response helper
sub _fail {
    my ($message, $code) = @_;

    if (!$message) {
        $message = 'Unknown error';
    }

    if (!$code) {
        $code = $Cpanel::NameServer::Constants::ERROR_GENERIC;
    }

    return ($code, $message);
}

# Cache all zones from PowerDNS
sub _cache_zones {
    my ($self) = @_;
    my @zones;

    # Fetch all zones
    my $res = $self->{'http_client'}->request(
        'GET',
        pdns_url(sprintf('/api/v1/servers/%s/zones', $self->{'server_id'}))
    );

    if (!$res->{'success'}) {
        die sprintf('Error querying the PowerDNS API: %s: %s', $res->{'status'}, $res->{'content'});
    }

    # Add each zone to our cache
    foreach my $zone (@{$res->{'decoded_content'}}) {
        # Also get the zone details with records
        my $zone_res = $self->{'http_client'}->request(
            'GET',
            pdns_url(sprintf('/api/v1/servers/%s/zones/%s', $self->{'server_id'}, $zone->{'id'}))
        );

        if ($zone_res->{'success'}) {
            push @zones, $zone_res->{'decoded_content'};
        }
    }

    return \@zones;
}

# Refresh a specific zone in the cache
sub _refresh_zone_in_cache {
    my ($self, $zone_id) = @_;
    
    # Get updated zone information
    my $res = $self->{'http_client'}->request(
        'GET',
        pdns_url(sprintf('/api/v1/servers/%s/zones/%s', $self->{'server_id'}, $zone_id))
    );

    if (!$res->{'success'}) {
        return;
    }
    
    # Update the zone in cache
    my $updated_zone = $res->{'decoded_content'};
    my $found = 0;
    
    for (my $i = 0; $i < scalar @{$local_cache}; $i++) {
        if (${$local_cache}[$i]->{'id'} eq $zone_id) {
            ${$local_cache}[$i] = $updated_zone;
            $found = 1;
            last;
        }
    }
    
    # Add to cache if not found
    if (!$found) {
        push @{$local_cache}, $updated_zone;
    }
}

# Get all nameservers for cached zones
sub _get_name_servers {
    my ($self) = @_;
    my @name_servers;

    foreach my $zone (@{$local_cache}) {
        # Extract NS records from the rrsets
        foreach my $rrset (@{$zone->{'rrsets'}}) {
            if ($rrset->{'type'} eq 'NS') {
                foreach my $record (@{$rrset->{'records'}}) {
                    push @name_servers, $record->{'content'};
                }
            }
        }
    }

    @name_servers = uniq @name_servers;
    return \@name_servers;
}

# Find a zone by name in the cache
sub _find_zone {
    my ($zone_name) = @_;
    
    # PowerDNS zones have trailing dots
    my $pdns_zone_name = $zone_name . '.';
    $pdns_zone_name =~ s/\.\.$/\./; # Avoid double dots

    return grep { $_->{'name'} eq $pdns_zone_name } @{$local_cache};
}

# Convert record data based on record type
sub _get_record_content {
    my ($record, $zone_name) = @_;
    my $type = uc($record->{'type'});
    my $content = '';
    
    if ($type eq 'MX') {
        $content = sprintf('%d %s', 
            $record->{'preference'}, 
            $record->{$RECORD_DATA_FIELDS->{'MX'}});
    }
    elsif ($type eq 'SRV') {
        $content = sprintf('%d %d %d %s',
            $record->{'priority'},
            $record->{'weight'},
            $record->{'port'},
            $record->{$RECORD_DATA_FIELDS->{'SRV'}});
    }
    elsif ($type eq 'TXT') {
        $content = Cpanel::DnsUtils::RR::encode_and_split_dns_txt_record_value(
            $record->{$RECORD_DATA_FIELDS->{'TXT'}});
    }
    else {
        $content = $record->{$RECORD_DATA_FIELDS->{$type}};
    }
    
    # Add trailing periods for certain record types
    if (grep { $type eq $_ } @RECORDS_NEEDING_TRAILING_PERIODS) {
        if ($content !~ /\.$/) {
            $content .= '.';
        }
    }
    
    return $content;
}

# Build a BIND-compatible zone file from PowerDNS zone data
sub _build_zone_file {
    my ($zone) = @_;
    my $zone_file = "";
    my $zone_name = $zone->{'name'};

    # Write the file's header with metadata and $ORIGIN
    $zone_file .= sprintf("; Domain:      %s\n", $zone_name);
    $zone_file .= sprintf("; PowerDNS ID: %s\n", $zone->{'id'});
    $zone_file .= sprintf("; Kind:        %s\n", $zone->{'kind'});
    $zone_file .= sprintf("; Created:     %s\n", $zone->{'account'} || 'unknown');
    $zone_file .= sprintf("\$ORIGIN %s\n\n", $zone_name);

    # Process all record sets
    foreach my $rrset (@{$zone->{'rrsets'}}) {
        my $record_name = $rrset->{'name'};
        
        # Convert to relative name if it's in the current zone
        if ($record_name eq $zone_name) {
            $record_name = '@';
        }
        elsif ($record_name =~ /\Q.$zone_name\E$/) {
            $record_name =~ s/\Q.$zone_name\E$//;
        }
        
        foreach my $record (@{$rrset->{'records'}}) {
            if ($record->{'disabled'}) {
                $zone_file .= sprintf("; DISABLED: %s %d IN %s %s\n", 
                    $record_name, $rrset->{'ttl'}, $rrset->{'type'}, $record->{'content'});
            }
            else {
                $zone_file .= sprintf("%s %d IN %s %s\n", 
                    $record_name, $rrset->{'ttl'}, $rrset->{'type'}, $record->{'content'});
            }
        }
        
        $zone_file .= "\n";
    }

    chomp $zone_file;
    return $zone_file;
}

1;