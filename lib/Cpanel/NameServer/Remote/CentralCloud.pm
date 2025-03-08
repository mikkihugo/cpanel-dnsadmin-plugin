# Status dashboard for WHM/cPanel integration
sub status_dashboard {
    my ($self, $request_id, $input, $raw_input) = @_;
    
    $self->log_info("Generating status dashboard");
    
    # Perform a fresh health check
    $self->_perform_health_check();
    
    # Start HTML output
    my $html = <<'HTML';
<!DOCTYPE html>
<html>
<head>
    <title>CentralCloud DNS Status Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; }
        h1 { color: #333; }
        .status-box { 
            border: 1px solid #ccc; 
            border-radius: 5px; 
            padding: 15px; 
            margin-bottom: 20px; 
        }
        .status-title { 
            font-weight: bold; 
            margin-bottom: 10px; 
        }
        .status-good { color: green; }
        .status-warning { color: orange; }
        .status-error { color: red; }
        .status-unknown { color: gray; }
        table { 
            width: 100%; 
            border-collapse: collapse; 
            margin-top: 10px;
        }
        th, td { 
            border: 1px solid #ddd; 
            padding: 8px; 
            text-align: left; 
        }
        th { background-color: #f2f2f2; }
        .zones-table { margin-top: 20px; }
    </style>
</head>
<body>
    <h1>CentralCloud DNS Status Dashboard</h1>
HTML

    # System status section
    $html .= <<HTML;
    <div class="status-box">
        <div class="status-title">System Status</div>
        
        <table>
            <tr>
                <th>Component</th>
                <th>Status</th>
                <th>Last Check</th>
            </tr>
            <tr>
                <td>PowerDNS API</td>
                <td class="status-$self->{'powerdns_status'}">$self->{'powerdns_status'}</td>
                <td>@{[scalar localtime($self->{'last_health_check'})]}</td>
            </tr>
            <tr>
                <td>HostBill API</td>
                <td class="status-$self->{'hostbill_status'}">$self->{'hostbill_status'}</td>
                <td>@{[scalar localtime($self->{'last_health_check'})]}</td>
            </tr>
        </table>
    </div>
HTML

    # Configuration section
    $html .= <<HTML;
    <div class="status-box">
        <div class="status-title">Configuration</div>
        
        <table>
            <tr>
                <th>Setting</th>
                <th>Value</th>
            </tr>
            <tr>
                <td>Dry Run Mode</td>
                <td>@{[$self->{'dry_run'} ? 'Enabled (No changes made to PowerDNS)' : 'Disabled (Making real changes)']}</td>
            </tr>
            <tr>
                <td>Development Mode</td>
                <td>@{[$self->{'dev_mode'} ? 'Enabled (Only operating on test domains)' : 'Disabled (Operating on all domains)']}</td>
            </tr>
            <tr>
                <td>Test Domains</td>
                <td>@{[join(', ', @{$self->{'test_domains'}})]}</td>
            </tr>
            <tr>
                <td>Auto-Repair</td>
                <td>@{[$self->{'enable_auto_repair'} ? 'Enabled' : 'Disabled']}</td>
            </tr>
            <tr>
                <td>Notifications</td>
                <td>@{[$self->{'enable_notifications'} ? 'Enabled' : 'Disabled']}</td>
            </tr>
            <tr>
                <td>Admin Email</td>
                <td>$self->{'admin_email'}</td>
            </tr>
            <tr>
                <td>PowerDNS API URL</td>
                <td>@{[$self->{'http_client'}->{'api_url'}]}</td>
            </tr>
            <tr>
                <td>HostBill URL</td>
                <td>$self->{'hostbill_url'}</td>
            </tr>
        </table>
    </div>
HTML

    # Zone Statistics
    my $zone_count = scalar(@{$local_cache});
    my $dev_zone_count = 0;
    my $dnssec_zone_count = 0;
    
    if ($zone_count > 0) {
        # Count zones matching criteria
        foreach my $zone (@{$local_cache}) {
            my $zone_name = $zone->{'name'};
            $zone_name =~ s/\.$//; # Remove trailing dot
            
            # Check if zone is in test domains
            foreach my $test_domain (@{$self->{'test_domains'}}) {
                if (lc($zone_name) eq lc($test_domain)) {
                    $dev_zone_count++;
                    last;
                }
            }
            
            # Check if zone has DNSSEC enabled
            if ($zone->{'dnssec'}) {
                $dnssec_zone_count++;
            }
        }
    }
    
    $html .= <<HTML;
    <div class="status-box">
        <div class="status-title">Zone Statistics</div>
        
        <table>
            <tr>
                <th>Metric</th>
                <th>Count</th>
            </tr>
            <tr>
                <td>Total Zones</td>
                <td>$zone_count</td>
            </tr>
            <tr>
                <td>Test Domains</td>
                <td>$dev_zone_count</td>
            </tr>
            <tr>
                <td>Zones with DNSSEC</td>
                <td>$dnssec_zone_count</td>
            </tr>
        </table>
    </div>
HTML

    # Recent zones section - show last 10 zones in cache
    $html .= <<'HTML';
    <div class="status-box">
        <div class="status-title">Recent Zones</div>
        
        <table class="zones-table">
            <tr>
                <th>Zone Name</th>
                <th>Type</th>
                <th>SOA Serial</th>
                <th>DNSSEC</th>
            </tr>
HTML

    # Add zone rows
    my $shown_zones = 0;
    my $max_zones = 10;  # Show at most 10 zones
    
    foreach my $zone (@{$local_cache}) {
        last if $shown_zones >= $max_zones;
        
        my $zone_name = $zone->{'name'};
        $zone_name =~ s/\.$//; # Remove trailing dot
        my $zone_kind = $zone->{'kind'} || 'Native';
        my $soa_serial = _get_soa_serial($zone);
        my $dnssec = $zone->{'dnssec'} ? 'Enabled' : 'Disabled';
        
        $html .= <<HTML;
            <tr>
                <td>$zone_name</td>
                <td>$zone_kind</td>
                <td>$soa_serial</td>
                <td>$dnssec</td>
            </tr>
HTML
        
        $shown_zones++;
    }
    
    # If no zones, show a message
    if ($shown_zones == 0) {
        $html .= <<'HTML';
            <tr>
                <td colspan="4">No zones found</td>
            </tr>
HTML
    }
    
    # Close the table and div
    $html .= <<'HTML';
        </table>
    </div>
HTML

    # Auto-repair section - show recent repairs
    $html .= <<'HTML';
    <div class="status-box">
        <div class="status-title">Auto-Repair Activity</div>
        
        <table>
            <tr>
                <th>Zone</th>
                <th>Repair Attempts</th>
            </tr>
HTML

    # Add auto-repair entries
    my $repair_count = 0;
    foreach my $zone_name (sort keys %{$self->{'repair_attempt_count'}}) {
        my $attempts = $self->{'repair_attempt_count'}->{$zone_name};
        
        $html .= <<HTML;
            <tr>
                <td>$zone_name</td>
                <td>$attempts</td>
            </tr>
HTML
        
        $repair_count++;
    }
    
    # If no repairs, show a message
    if ($repair_count == 0) {
        $html .= <<'HTML';
            <tr>
                <td colspan="2">No auto-repair activity</td>
            </tr>
HTML
    }
    
    # Close the table and div
    $html .= <<'HTML';
        </table>
    </div>
HTML

    # Footer with version info
    $html .= <<HTML;
    <div style="margin-top: 20px; text-align: center; color: #666; font-size: 12px;">
        CentralCloud DNS Clustering Plugin v$VERSION
        <br>
        Generated: @{[scalar localtime()]}
    </div>
</body>
</html>
HTML

    # Output the HTML
    $self->output($html);
    
    $self->log_info("Status dashboard generated successfully");
    return _success();
}

# Refresh a zone with auto-repair check
sub _refresh_zone_with_repair {
    my ($self, $zone_id, $cpanel_zone_data) = @_;
    
    # First, refresh the zone from PowerDNS
    my $fresh_zone = $self->_refresh_zone_from_powerdns($zone_id);
    
    if (!$fresh_zone) {
        $self->log_warn("Failed to refresh zone for repair check");
        return undef;
    }
    
    # If we have cPanel zone data, check for discrepancies and auto-repair if needed
    if ($cpanel_zone_data && $self->{'enable_auto_repair'}) {
        my $zone_name = $fresh_zone->{'name'};
        $zone_name =~ s/\.$//; # Remove trailing dot
        
        $self->_auto_repair_zone($zone_name, $cpanel_zone_data, $fresh_zone);
    }
    
    return $fresh_zone;
}

# Get zone with auto-repair integration
sub getzone {
    my ($self, $request_id, $input, $raw_input) = @_;
    chomp($input->{'zone'});

    $self->log_info(sprintf("Getting zone: %s (request ID: %s)", $input->{'zone'}, $request_id));

    # Check domain restrictions first (dev mode and cpanel domains)
    my @zones = $self->_find_zone($input->{'zone'});
    my $size = scalar @zones;

    if ($size > 1) {
        my $error_msg = sprintf('More than one match found for zone "%s"', $input->{'zone'});
        $self->log_error($error_msg);
        return _fail($error_msg);
    }

    if ($size == 0) {
        my $error_msg = sprintf('Zone "%s" not found', $input->{'zone'});
        $self->log_error($error_msg);
        return _fail($error_msg);
    }

    # Refresh the zone from PowerDNS to ensure we have the latest data
    my $zone_id = $zones[0]->{'id'};
    $self->log_debug(sprintf("Refreshing zone %s (ID: %s) from PowerDNS", $input->{'zone'}, $zone_id));
    
    # Get the latest zone data from PowerDNS
    my $fresh_zone = $self->_refresh_zone_from_powerdns($zone_id);
    
    if (!$fresh_zone) {
        my $error_msg = sprintf('Failed to refresh zone "%s" from PowerDNS', $input->{'zone'});
        $self->log_error($error_msg);
        return _fail($error_msg);
    }
    
    # Build the zone file
    my $zone_file = _build_zone_file($fresh_zone);
    $self->log_debug("Zone file built, size: " . length($zone_file) . " bytes");
    
    # Perform a health check occasionally
    if (time() - $self->{'last_health_check'} > $self->{'health_check_interval'}) {
        $self->_perform_health_check();
    }
    
    # Check for auto-repair if enabled
    if ($self->{'enable_auto_repair'}) {
        # For auto-repair, we need the cPanel zone data
        # We can get this from the zonedata parameter if it exists
        if ($input->{'zonedata'}) {
            $self->log_debug("Zone data provided, checking for auto-repair needs");
            $self->_auto_repair_zone($input->{'zone'}, $input->{'zonedata'}, $fresh_zone);
        }
    }
    
    $self->output($zone_file);
    
    $self->log_info(sprintf("Successfully retrieved zone: %s", $input->{'zone'}));
    return _success();
}

1;# Cache zones from PowerDNS that also exist in cPanel
sub _cache_zones {
    my ($self) = @_;
    my @zones;
    
    $self->log_debug("Caching zones from PowerDNS that match cPanel domains");
    
    # Get cPanel domains and create a lookup hash (with trailing dot for PowerDNS format)
    my @cpanel_domains = $self->_get_cpanel_domains();
    my %cpanel_domain_map = map { ($_ . '.') => 1 } @cpanel_domains;
    
    $self->log_debug(sprintf("Found %d domains in cPanel", scalar(@cpanel_domains)));
    
    # If in development mode, only include test domains
    if ($self->{'dev_mode'}) {
        my %test_domain_map;
        foreach my $domain (@{$self->{'test_domains'}}) {
            $test_domain_map{$domain . '.'} = 1;
            $self->log_debug("Adding test domain to allowed list: $domain");
        }
        
        # Filter cPanel domains to only include test domains
        my @filtered_domains;
        foreach my $domain (keys %cpanel_domain_map) {
            my $base_domain = $domain;
            $base_domain =~ s/\.$//;
            if ($test_domain_map{$domain}) {
                push @filtered_domains, $domain;
                $self->log_debug("Keeping domain in filter: $base_domain (in test domains)");
            } else {
                $self->log_debug("Filtering out domain: $base_domain (not in test domains)");
            }
        }
        
        # Replace original map with filtered map
        %cpanel_domain_map = map { $_ => 1 } @filtered_domains;
        $self->log_debug(sprintf("After test domain filtering: %d domains remain", scalar(keys %cpanel_domain_map)));
    }
    
    # Fetch all zones from PowerDNS
    my $res = $self->{'http_client'}->request(
        'GET',
        pdns_url(sprintf('/api/v1/servers/%s/zones', $self->{'server_id'}))
    );
    
    if (!$res->{'success'}) {
        my $error_msg = sprintf('Error querying the PowerDNS API: %s: %s', $res->{'status'}, $res->{'content'});
        $self->log_error($error_msg);
        die $error_msg;
    }
    
    # Filter zones to only include those that match cPanel domains
    my $zones_count = scalar(@{$res->{'decoded_content'}});
    $self->log_debug(sprintf("Found %d total zones in PowerDNS", $zones_count));
    
    foreach my $zone (@{$res->{'decoded_content'}}) {
        $self->log_debug(sprintf("Processing zone: %s", $zone->{'name'}));
        
        # Skip if we're filtering by cPanel domains and this zone isn't in cPanel
        if ($self->{'filter_by_cpanel_domains'} && !$cpanel_domain_map{$zone->{'name'}}) {
            $self->log_debug(sprintf("Skipping zone %s - not in cPanel", $zone->{'name'}));
            next;
        }
        
        # Skip if in development mode and not a test domain
        if ($self->{'dev_mode'}) {
            my $zone_name = $zone->{'name'};
            $zone_name =~ s/\.$//; # Remove trailing dot
            
            my $is_test_domain = 0;
            foreach my $test_domain (@{$self->{'test_domains'}}) {
                if (lc($zone_name) eq lc($test_domain)) {
                    $is_test_domain = 1;
                    last;
                }
            }
            
            if (!$is_test_domain) {
                $self->log_debug(sprintf("Skipping zone %s - dev mode enabled and not a test domain", $zone->{'name'}));
                next;
            }
            
            $self->log_debug(sprintf("Including zone %s - matches test domain", $zone->{'name'}));
        }
        
        # This zone exists in cPanel, so get full details and cache it
        $self->log_debug(sprintf("Fetching complete zone data for: %s", $zone->{'name'}));
        my $zone_res = $self->{'http_client'}->request(
            'GET',
            pdns_url(sprintf('/api/v1/servers/%s/zones/%s', $self->{'server_id'}, $zone->{'id'}))
        );

        if ($zone_res->{'success'}) {
            push @zones, $zone_res->{'decoded_content'};
            $self->log_debug(sprintf("Successfully cached zone %s", $zone->{'name'}));
        } else {
            $self->log_warn(sprintf("Failed to get details for zone %s: %s", 
                          $zone->{'name'}, $zone_res->{'content'}));
        }
    }
    
    $self->log_info(sprintf("Filtered %d total zones down to %d cPanel domains", 
                          $zones_count, scalar(@zones)));
    
    return \@zones;
}package Cpanel::NameServer::Remote::CentralCloud;

# An implementation of the cPanel dns clustering interface for CentralCloud
# Connects to PowerDNS API for DNS management

use strict;
use warnings;

use Cpanel::DnsUtils::RR         ();
use Cpanel::Encoder::URI         ();
use Cpanel::JSON                 ();
use Cpanel::JSON::XS             qw(encode_json decode_json);
use Cpanel::Logger               ();
use Cpanel::NameServer::Remote::CentralCloud::API;
use cPanel::PublicAPI            ();
use Cpanel::SocketIP             ();
use Cpanel::StringFunc::Match    ();
use Cpanel::ZoneFile             ();
use Cpanel::ZoneFile::Versioning ();
use HTTP::Date                   ();
use List::Util                   qw(min);
use List::MoreUtils              qw(any natatime none uniq);
use Time::Local                  qw(timegm);
use HTTP::Tiny                   ();
use Digest::SHA                  ();

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

# Log levels
use constant {
    LOG_ERROR => 1,
    LOG_WARN  => 2,
    LOG_INFO  => 3,
    LOG_DEBUG => 4
};

# Mapping from string to numeric log levels
my %LOG_LEVEL_MAP = (
    'error' => LOG_ERROR,
    'warn'  => LOG_WARN,
    'info'  => LOG_INFO,
    'debug' => LOG_DEBUG
);

# Build a new CentralCloud DNS module
sub new {
    my ($class, %args) = @_;
    
    # Initialize the self hash with configuration and defaults
    my $self = {
        'name'            => $args{'host'},
        'update_type'     => $args{'update_type'},
        'queue_callback'  => $args{'queue_callback'},
        'output_callback' => $args{'output_callback'},
        'server_id'       => 'localhost',  # Hardcoded to localhost
        
        # Logging - use log_level for debug too
        'log_level'       => $args{'log_level'} || 'warn',
        'log_file'        => $args{'log_file'} || '/var/log/centralcloud-plugin.log',
        
        # DNS Settings
        'default_ttl'     => $args{'default_ttl'} || 3600,
        'soa_refresh'     => $args{'soa_refresh'} || 10800,
        'soa_retry'       => $args{'soa_retry'} || 3600,
        'soa_expire'      => $args{'soa_expire'} || 604800,
        'soa_minimum'     => $args{'soa_minimum'} || 3600,
        
        # Domain filtering - always true
        'filter_by_cpanel_domains' => 1,
        
        # HostBill integration
        'hostbill_url'    => $args{'hostbill_url'} || 'https://portal.centralcloud.com',
        'hostbill_api_id' => $args{'hostbill_api_id'} || '',
        'hostbill_api_key' => $args{'hostbill_api_key'} || '',
        
        # Development mode - restrict to test domains only
        'dev_mode'        => 1,  # Default to enabled for safety
        'test_domains'    => ['test1.com', 'test2.com'],
        
        # Health check and monitoring
        'last_health_check' => 0,  # Unix timestamp of last health check
        'health_check_interval' => $args{'health_check_interval'} || 3600,  # Default: hourly
        'powerdns_status' => 'unknown',
        'hostbill_status' => 'unknown',
        
        # Notification settings
        'enable_notifications' => 1,  # Enable email notifications
        'admin_email'    => '',  # Will be fetched from cPanel config
        'notification_cooldown' => 3600,  # Don't send repeat notifications within this period (1 hour)
        'last_notification' => {
            'powerdns_down' => 0,
            'hostbill_down' => 0,
            'auto_repair' => 0,
        },
        
        # Auto-repair settings
        'enable_auto_repair' => 1,  # Enable automatic repair of discrepancies
        'max_repair_attempts' => 3,  # Maximum repair attempts per zone
        'repair_attempt_count' => {},  # Track repair attempts per zone
        
        # Store the original args for logging purposes
        '_args'           => \%args,
    };
    
    # Determine dry run mode based on update_type
    # update_type is set by cPanel based on the server type (standalone, writeonly, readwrite)
    if ($args{'update_type'} && $args{'update_type'} eq 'writeonly') {
        $self->{'dry_run'} = 0;  # Not a dry run, make real changes
    } else {
        # Default to dry run mode (for standalone or any other type)
        $self->{'dry_run'} = 1;  # Dry run mode, don't make any changes
    }
    
    # Set debug flag based on log level
    $self->{'debug'} = ($self->{'log_level'} && $self->{'log_level'} eq 'debug') ? 1 : 0;
    
    # Create HTTP client for PowerDNS API
    $self->{'http_client'} = Cpanel::NameServer::Remote::CentralCloud::API->new(
        'api_url'     => $args{'api_url'} || 'https://master.ns.centralcloud.net',
        'api_key'     => $args{'api_key'} || '',
        'timeout'     => $args{'api_timeout'} || 60,
        'debug'       => $self->{'debug'},
    );

    bless $self, $class;
    
    # Initialize logging
    $self->_init_logger();
    $self->log_info("CentralCloud plugin initialized with server_id: $self->{'server_id'}");
    $self->log_debug("API URL: " . $args{'api_url'});
    
    # Get admin email from cPanel config
    $self->_get_admin_email();
    
    # Log dry run status
    if ($self->{'dry_run'}) {
        $self->log_info("OPERATING IN DRY RUN MODE - No changes will be made to PowerDNS/HostBill");
    } else {
        $self->log_info("OPERATING IN WRITE MODE - Changes will be made to PowerDNS/HostBill");
    }
    
    # Log development mode status
    if ($self->{'dev_mode'}) {
        $self->log_info("DEVELOPMENT MODE ENABLED - Only operating on test domains: " . 
                       join(", ", @{$self->{'test_domains'}}));
    }
    
    # Perform initial health check
    $self->_perform_health_check();
    
    # Cache zones
    $self->log_debug("Caching zones from PowerDNS server");
    $local_cache = $self->_cache_zones();
    $self->log_info("Cached " . scalar(@{$local_cache}) . " zones from PowerDNS server");

    return $self;
}

# Initialize logging
sub _init_logger {
    my ($self) = @_;
    
    # Set default log level if not specified
    my $log_level_str = $self->{'log_level'} || 'warn';
    my $log_level = $LOG_LEVEL_MAP{$log_level_str} || LOG_WARN;
    
    $self->{'_log_level'} = $log_level;
    
    # Create logger if not already done
    if (!defined $self->{'logger'}) {
        $self->{'logger'} = Cpanel::Logger->new(
            'logger_name' => 'centralcloud_plugin',
            'logfile'     => $self->{'log_file'},
            'timestamp'   => 1,
        );
    }
    
    return $self;
}

# Log a message at specified level
sub _log {
    my ($self, $level, $message) = @_;
    
    # Initialize logger if needed
    if (!defined $self->{'_log_level'}) {
        $self->_init_logger();
    }
    
    # Only log if the level is at or below the configured level
    if ($level <= $self->{'_log_level'}) {
        my $level_str = 'UNKNOWN';
        
        if ($level == LOG_ERROR) {
            $level_str = 'ERROR';
        }
        elsif ($level == LOG_WARN) {
            $level_str = 'WARN';
        }
        elsif ($level == LOG_INFO) {
            $level_str = 'INFO';
        }
        elsif ($level == LOG_DEBUG) {
            $level_str = 'DEBUG';
        }
        
        # Format the message with the level
        my $formatted_message = sprintf("[%s] %s", $level_str, $message);
        
        # Log through Cpanel::Logger
        $self->{'logger'}->info($formatted_message);
        
        # Also output to debug if debug mode is on
        if ($self->{'debug'}) {
            $self->output("$formatted_message\n");
        }
    }
    
    return $self;
}

# Convenience methods for different log levels
sub log_error {
    my ($self, $message) = @_;
    return $self->_log(LOG_ERROR, $message);
}

sub log_warn {
    my ($self, $message) = @_;
    return $self->_log(LOG_WARN, $message);
}

sub log_info {
    my ($self, $message) = @_;
    return $self->_log(LOG_INFO, $message);
}

sub log_debug {
    my ($self, $message) = @_;
    return $self->_log(LOG_DEBUG, $message);
}

# Get list of domains hosted on this cPanel server
sub _get_cpanel_domains {
    my ($self) = @_;
    my @domains;
    
    $self->log_debug("Getting list of cPanel domains");
    
    # Method 1: Use Cpanel::DomainLookup
    if (eval { require Cpanel::DomainLookup; 1 }) {
        $self->log_debug("Using Cpanel::DomainLookup to get domain list");
        my $domain_data = Cpanel::DomainLookup::get_cpanel_domain_data();
        @domains = keys %{$domain_data};
    }
    # Method 2: Fallback to WHM API
    else {
        $self->log_debug("Falling back to WHM API to get domain list");
        # Use the WHM API to get a list of accounts and their domains
        my $whmapi = cPanel::PublicAPI::WHM->new();
        my $accounts = $whmapi->listaccts();
        
        if ($accounts && ref $accounts eq 'HASH' && $accounts->{acct}) {
            foreach my $account (@{$accounts->{acct}}) {
                if ($account->{domain}) {
                    push @domains, $account->{domain};
                    $self->log_debug("Found domain: $account->{domain} for account: $account->{user}");
                    
                    # Also add addon domains if available
                    if ($account->{user}) {
                        my $userapi = cPanel::PublicAPI->new(
                            'user' => $account->{user}
                        );
                        
                        my $addons = $userapi->api2_query(
                            'user' => $account->{user},
                            'module' => 'AddonDomain',
                            'func' => 'listaddondomains'
                        );
                        
                        if ($addons && $addons->{cpanelresult} && $addons->{cpanelresult}->{data}) {
                            foreach my $addon (@{$addons->{cpanelresult}->{data}}) {
                                if ($addon->{domain}) {
                                    push @domains, $addon->{domain};
                                    $self->log_debug("Found addon domain: $addon->{domain} for account: $account->{user}");
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    $self->log_info(sprintf("Found %d domains on local cPanel server", scalar @domains));
    return @domains;
}

# Get nameserver and admin email from cPanel configuration for a domain
sub _get_domain_settings {
    my ($self, $domain) = @_;
    
    $self->log_debug("Getting nameserver and admin email settings for domain: $domain");
    
    # Default values in case we can't retrieve from cPanel
    my $ns_hostname = "ns1.$domain.";
    my $admin_email = "hostmaster.$domain.";
    
    # Try to get nameserver from cPanel config
    if (eval { require Cpanel::Config::LoadCpConf; 1 }) {
        my $cpanel_conf = Cpanel::Config::LoadCpConf::loadcpconf();
        
        # Get primary nameserver
        if ($cpanel_conf->{'nameserver'}) {
            $ns_hostname = $cpanel_conf->{'nameserver'};
            $ns_hostname .= '.' unless $ns_hostname =~ /\.$/;
            $self->log_debug("Using nameserver from cPanel config: $ns_hostname");
        }
        
        # Get admin email
        if ($cpanel_conf->{'hostmaster'}) {
            $admin_email = $cpanel_conf->{'hostmaster'};
            $admin_email =~ s/@/./; # SOA format uses . instead of @ for email
            $admin_email .= '.' unless $admin_email =~ /\.$/;
            $self->log_debug("Using admin email from cPanel config: $admin_email");
        }
    }
    
    # Check reseller customizations for this domain
    my $domain_owner = $self->_get_domain_owner($domain);
    if ($domain_owner) {
        # Look for reseller-specific nameserver configuration
        if (eval { require Cpanel::Resellers; 1 }) {
            my $reseller = Cpanel::Resellers::get_reseller_by_user($domain_owner);
            
            if ($reseller) {
                # Check for reseller-specific nameserver
                my $reseller_nameservers = Cpanel::Resellers::get_reseller_nameservers($reseller);
                if ($reseller_nameservers && $reseller_nameservers->[0]) {
                    $ns_hostname = $reseller_nameservers->[0];
                    $ns_hostname .= '.' unless $ns_hostname =~ /\.$/;
                    $self->log_debug("Using reseller nameserver: $ns_hostname for domain: $domain");
                }
            }
        }
    }
    
    $self->log_debug("Final nameserver: $ns_hostname and admin email: $admin_email for domain: $domain");
    return ($ns_hostname, $admin_email);
}

# Get the cPanel username that owns a domain
sub _get_domain_owner {
    my ($self, $domain) = @_;
    my $owner = '';
    
    # Try to find the owner of this domain
    if (eval { require Cpanel::DomainLookup; 1 }) {
        my $domain_data = Cpanel::DomainLookup::get_domain_info($domain);
        if ($domain_data && $domain_data->{'user'}) {
            $owner = $domain_data->{'user'};
            $self->log_debug("Domain $domain is owned by cPanel user: $owner");
        }
    }
    
    return $owner;
}

# Add a zone to the PowerDNS server
sub addzoneconf {
    my ($self, $request_id, $input, $raw_input) = @_;
    chomp($input->{'zone'});

    $self->log_info(sprintf("Adding zone configuration for: %s (request ID: %s)", $input->{'zone'}, $request_id));

    # Format zone name properly (with trailing dot)
    my $zone_name = $input->{'zone'};
    $zone_name .= '.' unless $zone_name =~ /\.$/;

    # Get nameserver and admin email from cPanel configuration
    my ($ns_hostname, $admin_email) = $self->_get_domain_settings($input->{'zone'});
    
    # Create a minimal SOA record for the new zone
    my $soa_content = sprintf("%s %s %d %d %d %d %d",
        $ns_hostname,
        $admin_email,
        time(),
        $self->{'soa_refresh'},
        $self->{'soa_retry'},
        $self->{'soa_expire'},
        $self->{'soa_minimum'}
    );

    $self->log_debug(sprintf("Creating zone with SOA: %s", $soa_content));

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
                'ttl' => $self->{'default_ttl'},
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
                'ttl' => $self->{'default_ttl'},
                'records' => [
                    {
                        'content' => $ns_hostname,
                        'disabled' => JSON::false,
                    }
                ]
            }
        ]
    };

    # Check if we're in dry run mode
    if ($self->{'dry_run'}) {
        $self->log_info("[DRY RUN] Would add zone $zone_name to PowerDNS - NO CHANGES MADE");
        
        # Create a mock zone for the local cache in dry run mode
        my $mock_zone = {
            'id' => 'dry-run-' . time() . '-' . substr(Digest::SHA::sha256_hex($zone_name), 0, 8),
            'name' => $zone_name,
            'kind' => 'Native',
            'rrsets' => $request_body->{'rrsets'},
        };
        
        # Add the mock zone to the local cache
        push @{$local_cache}, $mock_zone;
        
        $self->output(sprintf("[DRY RUN] Would add zone \"%s\" to %s\n", $input->{'zone'}, $self->{'name'}));
        return _success();
    }
    
    # If not in dry run mode, create the zone in PowerDNS
    $self->log_debug("Sending zone creation request to PowerDNS API");
    my $res = $self->{'http_client'}->request(
        'POST',
        pdns_url(sprintf('/api/v1/servers/%s/zones', $self->{'server_id'})),
        {'content' => encode_json($request_body)}
    );

    if (!$res->{'success'}) {
        my $error_msg = sprintf('Unable to save zone "%s": %s: %s', 
                      $input->{'zone'}, $res->{'status'}, $res->{'content'});
        $self->log_error($error_msg);
        return _fail($error_msg);
    }

    # Add the zone to the local cache
    my $zone = $res->{'decoded_content'};
    push @{$local_cache}, $zone;

    $self->log_info(sprintf("Successfully added zone \"%s\" to %s", $input->{'zone'}, $self->{'name'}));
    $self->output(sprintf("Added zone \"%s\" to %s\n", $input->{'zone'}, $self->{'name'}));
    return _success();
}

# Get all zone files from PowerDNS
sub getallzones {
    my ($self, $request_id, $input, $raw_input) = @_;
    
    $self->log_info("Getting all zones (request ID: $request_id)");
    $self->log_debug("Number of zones in cache: " . scalar(@{$local_cache}));

    # For each zone, refresh from PowerDNS first
    my @refreshed_zones;
    foreach my $zone (@{$local_cache}) {
        my $zone_id = $zone->{'id'};
        my $zone_name = $zone->{'name'};
        $self->log_debug("Processing zone: $zone_name");
        
        # Refresh the zone data
        my $fresh_zone = $self->_refresh_zone_from_powerdns($zone_id);
        if ($fresh_zone) {
            push @refreshed_zones, $fresh_zone;
        } else {
            # If refresh fails, use the cached version
            push @refreshed_zones, $zone;
        }
    }
    
    # Output each zone
    foreach my $zone (@refreshed_zones) {
        $self->output(sprintf(
            'cpdnszone-%s=%s&',
            Cpanel::Encoder::URI::uri_encode_str($zone->{'name'}),
            Cpanel::Encoder::URI::uri_encode_str(_build_zone_file($zone))
        ));
    }
    
    $self->log_info("Successfully retrieved all zones");
    return _success();
}

# Get the IP addresses of the nameservers
sub getips {
    my ($self, $request_id, $input, $raw_input) = @_;
    my @ips;

    $self->log_info("Getting IP addresses of nameservers (request ID: $request_id)");
    
    my $name_servers = $self->_get_name_servers();
    $self->log_debug("Found " . scalar(@{$name_servers}) . " nameservers");
    
    foreach my $name_server (@{$name_servers}) {
        my $ip = Cpanel::SocketIP::_resolveIpAddress($name_server);
        if ($ip) {
            push @ips, $ip;
            $self->log_debug("Resolved nameserver $name_server to IP: $ip");
        } else {
            $self->log_warn("Could not resolve nameserver: $name_server");
        }
    }

    $self->output(join("\n", @ips) . "\n");
    $self->log_info("Retrieved " . scalar(@ips) . " IP addresses");
    return _success();
}

# Get the nameservers path
sub getpath {
    my ($self, $request_id, $input, $raw_input) = @_;

    $self->log_info("Getting nameserver paths (request ID: $request_id)");
    
    my $name_servers = $self->_get_name_servers();
    $self->log_debug("Returning " . scalar(@{$name_servers}) . " nameservers");
    
    $self->output(join("\n", @{$name_servers}) . "\n");
    return _success();
}

# Get a single zone
sub getzone {
    my ($self, $request_id, $input, $raw_input) = @_;
    chomp($input->{'zone'});

    $self->log_info(sprintf("Getting zone: %s (request ID: %s)", $input->{'zone'}, $request_id));

    # Check domain restrictions first (dev mode and cpanel domains)
    my @zones = $self->_find_zone($input->{'zone'});
    my $size = scalar @zones;

    if ($size > 1) {
        my $error_msg = sprintf('More than one match found for zone "%s"', $input->{'zone'});
        $self->log_error($error_msg);
        return _fail($error_msg);
    }

    if ($size == 0) {
        my $error_msg = sprintf('Zone "%s" not found', $input->{'zone'});
        $self->log_error($error_msg);
        return _fail($error_msg);
    }

    # Refresh the zone from PowerDNS to ensure we have the latest data
    my $zone_id = $zones[0]->{'id'};
    $self->log_debug(sprintf("Refreshing zone %s (ID: %s) from PowerDNS", $input->{'zone'}, $zone_id));
    
    # Get the latest zone data from PowerDNS
    my $fresh_zone = $self->_refresh_zone_from_powerdns($zone_id);
    
    if (!$fresh_zone) {
        my $error_msg = sprintf('Failed to refresh zone "%s" from PowerDNS', $input->{'zone'});
        $self->log_error($error_msg);
        return _fail($error_msg);
    }
    
    my $zone_file = _build_zone_file($fresh_zone);
    $self->log_debug("Zone file built, size: " . length($zone_file) . " bytes");
    $self->output($zone_file);
    
    $self->log_info(sprintf("Successfully retrieved zone: %s", $input->{'zone'}));
    return _success();
}

# List all zones
sub getzonelist {
    my ($self, $request_id, $input, $raw_input) = @_;
    
    $self->log_info("Getting zone list (request ID: $request_id)");
    
    my @zones = map { $_->{'name'} =~ s/\.$//r } @{$local_cache};
    $self->log_debug("Found " . scalar(@zones) . " zones in cache");

    $self->output(join("\n", @zones) . "\n");
    
    $self->log_info("Successfully retrieved zone list");
    return _success();
}

# Get multiple zones
sub getzones {
    my ($self, $request_id, $input, $raw_input) = @_;
    chomp($input->{'zone'});

    if (defined $input->{'zones'}) {
        chomp($input->{'zones'});
    }

    my $zones_param = $input->{'zones'} || $input->{'zone'};
    $self->log_info(sprintf("Getting multiple zones: %s (request ID: %s)", $zones_param, $request_id));

    my @zones;
    my @search_for = split(/\,/, $zones_param);
    $self->log_debug("Searching for " . scalar(@search_for) . " zones");

    # Look for zones in the cache
    foreach my $zone_name (@search_for) {
        chomp $zone_name;
        $self->log_debug("Looking for zone: $zone_name");

        my @found_zones = $self->_find_zone($zone_name);

        # Only render the zone if it's found in the cache
        if ((scalar @found_zones) == 1) {
            # Refresh the zone from PowerDNS
            my $zone_id = $found_zones[0]->{'id'};
            my $fresh_zone = $self->_refresh_zone_from_powerdns($zone_id);
            
            if ($fresh_zone) {
                push @zones, $fresh_zone;
                $self->log_debug("Found and refreshed zone: $zone_name");
            } else {
                push @zones, $found_zones[0];  # Use cached version if refresh fails
                $self->log_debug("Found zone but failed to refresh: $zone_name");
            }
        } else {
            $self->log_warn("Zone not found or multiple matches: $zone_name");
        }
    }

    $self->log_debug("Found " . scalar(@zones) . " zones to render");
    
    # Render zones to BIND-compatible zone files
    foreach my $zone (@zones) {
        my $zone_name = $zone->{'name'} =~ s/\.$//r;
        $self->log_debug("Rendering zone: $zone_name");
        
        my $zone_file = _build_zone_file($zone);
        $self->output(sprintf(
            'cpdnszone-%s=%s&',
            Cpanel::Encoder::URI::uri_encode_str($zone_name),
            Cpanel::Encoder::URI::uri_encode_str($zone_file)
        ));
    }

    $self->log_info(sprintf("Successfully retrieved %d zones", scalar(@zones)));
    return _success();
}

# Add a zone and save its contents in one operation
sub quickzoneadd {
    my ($self, $request_id, $input, $raw_input) = @_;

    $self->log_info(sprintf("Quick zone add for: %s (request ID: %s)", $input->{'zone'}, $request_id));
    return $self->savezone(sprintf('%s_1', $request_id), $input, $raw_input);
}

# Remove a zone
sub removezone {
    my ($self, $request_id, $input, $raw_input) = @_;
    chomp($input->{'zone'});

    $self->log_info(sprintf("Removing zone: %s (request ID: %s)", $input->{'zone'}, $request_id));

    # Make sure the zone exists
    my @zones = $self->_find_zone($input->{'zone'});
    my $size = scalar @zones;

    if ($size > 1) {
        my $error_msg = sprintf('More than one match found for zone "%s"', $input->{'zone'});
        $self->log_error($error_msg);
        return _fail($error_msg);
    }

    if ($size == 0) {
        my $error_msg = sprintf('Zone "%s" not found', $input->{'zone'});
        $self->log_error($error_msg);
        return _fail($error_msg);
    }

    # Don't remove the zone from PowerDNS - it will be handled by PowerDNS and HostBill
    # Just remove from our local cache and return success
    my $zone_id = $zones[0]->{'id'};
    $self->log_debug("Zone will be removed by HostBill/PowerDNS, just updating local cache");
    
    # Remove the zone from the local cache
    $self->log_debug("Removing zone from local cache");
    my @new_cache = grep { $_->{'id'} ne $zone_id } @{$local_cache};
    $local_cache = \@new_cache;

    $self->log_info(sprintf("Successfully marked zone as removed: %s", $input->{'zone'}));
    $self->output(sprintf("%s => marked for removal\n", $input->{'zone'}));
    return _success();
}

# Remove multiple zones
sub removezones {
    my ($self, $request_id, $input, $raw_input) = @_;
    chomp($input->{'zone'});

    if (defined $input->{'zones'}) {
        chomp($input->{'zones'});
    }

    my $zones_param = $input->{'zones'} || $input->{'zone'};
    $self->log_info(sprintf("Removing multiple zones: %s (request ID: %s)", $zones_param, $request_id));

    my @zones;
    my @search_for = split(/\,/, $zones_param);
    $self->log_debug("Searching for " . scalar(@search_for) . " zones to remove");

    # Look for zones in the cache
    foreach my $zone_name (@search_for) {
        chomp $zone_name;
        $self->log_debug("Looking for zone: $zone_name");

        my @found_zones = $self->_find_zone($zone_name);

        if ((scalar @found_zones) == 1) {
            push @zones, $found_zones[0];
            $self->log_debug("Found zone: $zone_name");
        } else {
            $self->log_warn("Zone not found or multiple matches: $zone_name");
        }
    }

    # Mark each zone for removal and fail out on the first error
    my $count = 0;
    $self->log_debug("Marking " . scalar(@zones) . " zones for removal");
    
    foreach my $zone (@zones) {
        my $zone_name = $zone->{'name'} =~ s/\.$//r;
        $self->log_debug("Marking zone for removal: $zone_name");
        
        my ($code, $message) = $self->removezone(
            sprintf('%s_%s', $request_id, $count), 
            {'zone' => $zone_name}, 
            {}
        );

        if ($code != $Cpanel::NameServer::Constants::SUCCESS) {
            $self->log_error("Failed to mark zone $zone_name for removal: $message");
            return _fail($message);
        }

        $count++;
    }

    $self->log_info(sprintf("Successfully marked %d zones for removal", $count));
    return _success();
}

# Save zone contents
sub savezone {
    my ($self, $request_id, $input, $raw_input) = @_;
    chomp($input->{'zone'});

    $self->log_info(sprintf("Saving zone: %s (request ID: %s)", $input->{'zone'}, $request_id));

    # Format zone name properly (with trailing dot for PowerDNS)
    my $zone_name = $input->{'zone'};
    my $pdns_zone_name = $zone_name . '.';
    $pdns_zone_name =~ s/\.\.$/\./; # Avoid double dots

    # Check if the zone exists
    my @zones = $self->_find_zone($zone_name);
    my $size = scalar @zones;
    my $zone_exists = $size == 1;

    if ($size > 1) {
        my $error_msg = sprintf('More than one match found for zone "%s"', $input->{'zone'});
        $self->log_error($error_msg);
        return _fail($error_msg);
    }

    # Parse the zone file from cPanel
    $self->log_debug("Parsing zone file from cPanel");
    my $local_zone = eval {
        Cpanel::ZoneFile->new('domain' => $input->{'zone'}, 'text' => $input->{'zonedata'});
    };

    if (!$local_zone || $local_zone->{'error'}) {
        my $error_msg = sprintf(
            "%s: Unable to save the zone %s on the remote server [%s] (Could not parse zonefile%s)",
            __PACKAGE__,
            $input->{'zone'},
            $self->{'name'},
            $local_zone ? sprintf(' - %s', $local_zone->{'error'}) : ''
        );
        $self->log_error($error_msg);
        return _fail($error_msg, $Cpanel::NameServer::Constants::ERROR_GENERIC_LOGGED);
    }

    # Check for dry run mode
    if ($self->{'dry_run'}) {
        $self->log_info(sprintf("[DRY RUN] Would save zone %s - NO CHANGES MADE", $zone_name));
        
        # If zone doesn't exist, we would create it first
        if (!$zone_exists) {
            $self->log_info("[DRY RUN] Would create new zone $zone_name first");
        }
        
        # Count records that would be updated
        my $record_count = scalar(@{$local_zone->{'dnszone'}});
        $self->log_info(sprintf("[DRY RUN] Would update %d records for zone %s", 
                               $record_count, $zone_name));
        
        $self->output(sprintf("[DRY RUN] Would save zone \"%s\" with %d records\n", 
                             $input->{'zone'}, $record_count));
        return _success();
    }
    
    # Add the zone if needed before updating records
    if (!$zone_exists) {