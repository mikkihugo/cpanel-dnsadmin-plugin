package Cpanel::NameServer::Setup::Remote::CentralCloud;

# Set up the CentralCloud backend for use in a cPanel DNS cluster
# Connects to PowerDNS API for DNS management and HostBill for DNSSEC

use strict;
use warnings;

use Cpanel::FileUtils::Copy ();
use Cpanel::JSON::XS        ();
use Cpanel::NameServer::Remote::CentralCloud::API;
use Whostmgr::ACLS          ();

our $VERSION = '0.1.0';

Whostmgr::ACLS::init_acls();

sub setup {
    my $self = shift;
    my %OPTS = @_;

    # Validate permissions
    if (!Whostmgr::ACLS::checkacl('clustering')) {
        return 0, 'User does not have the clustering ACL enabled.';
    }

    # Validate parameter existence
    if (!defined $OPTS{'api_url'}) {
        return 0, 'No API URL given';
    }

    if (!defined $OPTS{'api_key'}) {
        return 0, 'No API key given';
    }

    # Validate HostBill parameters
    if (!defined $OPTS{'hostbill_url'} || !defined $OPTS{'hostbill_api_id'} || !defined $OPTS{'hostbill_api_key'}) {
        return 0, 'HostBill API URL, ID and Key are required for DNSSEC support';
    }

    my $api_url         = $OPTS{'api_url'};
    my $api_key         = $OPTS{'api_key'};
    my $hostbill_url    = $OPTS{'hostbill_url'};
    my $hostbill_api_id = $OPTS{'hostbill_api_id'};
    my $hostbill_api_key = $OPTS{'hostbill_api_key'};
    my $log_level       = $OPTS{'log_level'} || 'warn';
    my $debug           = $log_level eq 'debug' ? 1 : 0;

    # Validate parameter values
    $api_url =~ tr/\r\n\f\0//d;
    $api_key =~ tr/\r\n\f\0//d;
    $hostbill_url =~ tr/\r\n\f\0//d;
    $hostbill_api_id =~ tr/\r\n\f\0//d;
    $hostbill_api_key =~ tr/\r\n\f\0//d;

    if (!$api_url) {
        return 0, 'Invalid API URL given';
    }

    if (!$api_key) {
        return 0, 'Invalid API key given';
    }

    if (!$hostbill_url) {
        return 0, 'Invalid HostBill URL given';
    }

    if (!$hostbill_api_id || !$hostbill_api_key) {
        return 0, 'Invalid HostBill API credentials given';
    }

    # Validate the config by connecting to PowerDNS API
    my ($valid, $validation_message) = _validate_config($api_url, $api_key);

    if (!$valid) {
        return 0, sprintf(
            'Unable to validate your configuration: %s. Please verify your CentralCloud API URL and key',
            $validation_message
        );
    }

    # Save the configuration file
    my ($saved, $save_message) = _save_config($ENV{'REMOTE_USER'}, %OPTS);

    if (!$saved) {
        return 0, $save_message;
    }

    # Return success, message, empty string, and module identifier
    return 1, 'The trust relationship with CentralCloud has been established.', '', 'centralcloud';
}

sub get_config {
    my %config = (
        'options' => [
            # Basic PowerDNS API Configuration
            {
                'name'        => 'api_url',
                'type'        => 'text',
                'locale_text' => 'PowerDNS API URL',
                'default'     => 'https://master.ns.centralcloud.net',
                'required'    => 1,
            },
            {
                'name'        => 'api_key',
                'type'        => 'text',
                'locale_text' => 'PowerDNS API Key',
                'required'    => 1,
            },
            
            # Logging Configuration
            {
                'name'        => 'log_level',
                'locale_text' => 'Log Level',
                'type'        => 'select',
                'options'     => ['error', 'warn', 'info', 'debug'],
                'default'     => 'warn',
            },
            {
                'name'        => 'log_file',
                'type'        => 'text',
                'locale_text' => 'Log File Path',
                'default'     => '/var/log/centralcloud-plugin.log',
            },
            
            # DNS Record Defaults
            {
                'name'        => 'default_ttl',
                'locale_text' => 'Default TTL for records (seconds)',
                'type'        => 'text',
                'default'     => '3600',
            },
            
            # SOA Record Defaults
            {
                'name'        => 'soa_refresh',
                'locale_text' => 'SOA Refresh (seconds)',
                'type'        => 'text',
                'default'     => '10800',
            },
            {
                'name'        => 'soa_retry',
                'locale_text' => 'SOA Retry (seconds)',
                'type'        => 'text',
                'default'     => '3600',
            },
            {
                'name'        => 'soa_expire',
                'locale_text' => 'SOA Expire (seconds)',
                'type'        => 'text',
                'default'     => '604800',
            },
            {
                'name'        => 'soa_minimum',
                'locale_text' => 'SOA Minimum (seconds)',
                'type'        => 'text',
                'default'     => '3600',
            },
            
            # HostBill Integration for DNSSEC
            {
                'name'        => 'hostbill_url',
                'type'        => 'text',
                'locale_text' => 'HostBill URL',
                'default'     => 'https://portal.centralcloud.com',
                'required'    => 1,
            },
            {
                'name'        => 'hostbill_api_id',
                'type'        => 'text',
                'locale_text' => 'HostBill API ID',
                'required'    => 1,
            },
            {
                'name'        => 'hostbill_api_key',
                'type'        => 'text',
                'locale_text' => 'HostBill API Key',
                'required'    => 1,
            },
            
            # API Connection Settings
            {
                'name'        => 'api_timeout',
                'type'        => 'text',
                'locale_text' => 'API Connection Timeout (seconds)',
                'default'     => '60',
            },
        ],
        'name' => 'CentralCloud',
        'companyids' => [150, 477, 425, 7],  # Standard cPanel company IDs
    );

    return wantarray ? %config : \%config;
}

# Validate the PowerDNS API configuration
sub _validate_config {
    my ($api_url, $api_key) = @_;
    
    # Try to create an API client with the given credentials
    my $http_client = eval {
        Cpanel::NameServer::Remote::CentralCloud::API->new(
            api_url => $api_url,
            api_key => $api_key,
        );
    };

    if ($@ ne '') {
        return 0, $@;
    }

    # Check if we can access the server
    my $res = $http_client->request(
        'GET', 
        '/api/v1/servers/localhost'
    );

    if (!$res->{'success'}) {
        return 0, sprintf('Error connecting to PowerDNS server: %s: %s', 
                         $res->{'status'}, $res->{'content'});
    }

    return 1, 'configuration is valid';
}

# Save the DNS trust configuration file
sub _save_config {
    my ($safe_remote_user, %OPTS) = @_;
    $safe_remote_user =~ s/\///g;

    # Make sure the config directory exists
    my $CLUSTER_ROOT     = '/var/cpanel/cluster';
    my $USER_ROOT        = $CLUSTER_ROOT . '/' . $safe_remote_user;
    my $CONFIG_ROOT      = $USER_ROOT . '/config';
    my $USER_CONFIG_FILE = $CONFIG_ROOT . '/centralcloud';
    my $ROOT_CONFIG_FILE = $CLUSTER_ROOT . '/root/config/centralcloud';

    foreach my $path ($CLUSTER_ROOT, $USER_ROOT, $CONFIG_ROOT) {
        if (!-e $path) {
            mkdir $path, 700;
        }
    }

    # Write the config file
    if (open my $fh, '>', $USER_CONFIG_FILE) {
        chmod 0600, $USER_CONFIG_FILE or warn "Failed to secure permissions on cluster configuration: $!";
        
        # Write version first
        print {$fh} "#version 2.0\n";
        
        # Write all config parameters
        foreach my $key (sort keys %OPTS) {
            next if $key eq 'self'; # Skip the object reference
            my $value = defined $OPTS{$key} ? $OPTS{$key} : '';
            print {$fh} "$key=$value\n";
        }
        
        # Module identifier for DNS cluster must match the module name
        print {$fh} "module=CentralCloud\n";
        
        close $fh;
    } else {
        warn "Could not write DNS trust configuration file: $!";
        return 0, "The trust relationship could not be established, please examine /usr/local/cpanel/logs/error_log for more information.";
    }

    if (!-e $ROOT_CONFIG_FILE && Whostmgr::ACLS::hasroot()) {
        Cpanel::FileUtils::Copy::safecopy($USER_CONFIG_FILE, $ROOT_CONFIG_FILE);
    }

    return 1, 'saved DNS trust configuration';
}

1;