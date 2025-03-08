package Cpanel::NameServer::Setup::Remote::PowerDNS;

# Set up the PowerDNS backend for use in a cPanel DNS cluster
# Adapted from the StackPath DNS plugin

use strict;
use warnings;

use Cpanel::FileUtils::Copy ();
use Cpanel::JSON::XS        ();
use Cpanel::NameServer::Remote::PowerDNS::API;
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

    if (!defined $OPTS{'server_id'}) {
        $OPTS{'server_id'} = 'localhost';  # Default server ID
    }

    my $api_url    = $OPTS{'api_url'};
    my $api_key    = $OPTS{'api_key'};
    my $server_id  = $OPTS{'server_id'};
    my $debug      = $OPTS{'debug'} ? 1 : 0;

    # Validate parameter values
    $api_url =~ tr/\r\n\f\0//d;
    $api_key =~ tr/\r\n\f\0//d;
    $server_id =~ tr/\r\n\f\0//d;

    if (!$api_url) {
        return 0, 'Invalid API URL given';
    }

    if (!$api_key) {
        return 0, 'Invalid API key given';
    }

    if (!$server_id) {
        return 0, 'Invalid server ID given';
    }

    # Validate the config by connecting to PowerDNS API
    my ($valid, $validation_message) = _validate_config($api_url, $api_key, $server_id);

    if (!$valid) {
        return 0, sprintf(
            'Unable to validate your configuration: %s. Please verify your PowerDNS API URL and key',
            $validation_message
        );
    }

    # Save the configuration file
    my ($saved, $save_message) = _save_config($ENV{'REMOTE_USER'}, $api_url, $api_key, $server_id, $debug);

    if (!$saved) {
        return 0, $save_message;
    }

    return 1, 'The trust relationship with PowerDNS has been established.', '', 'powerdns';
}

sub get_config {
    my %config = (
        'options' => [
            {
                'name'        => 'api_url',
                'type'        => 'text',
                'locale_text' => 'PowerDNS API URL (e.g., http://localhost:8081)',
            },
            {
                'name'        => 'api_key',
                'type'        => 'text',
                'locale_text' => 'PowerDNS API Key',
            },
            {
                'name'        => 'server_id',
                'type'        => 'text',
                'locale_text' => 'PowerDNS Server ID',
                'default'     => 'localhost',
            },
            {
                'name'        => 'debug',
                'locale_text' => 'Debug mode',
                'type'        => 'binary',
                'default'     => 0,
            },
        ],
        'name' => 'PowerDNS',
        'companyids' => [150, 477, 425, 7],  # Standard cPanel company IDs
    );

    return wantarray ? %config : \%config;
}

# Validate the PowerDNS API configuration
sub _validate_config {
    my ($api_url, $api_key, $server_id) = @_;
    
    # Try to create an API client with the given credentials
    my $http_client = eval {
        Cpanel::NameServer::Remote::PowerDNS::API->new(
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
        sprintf('/api/v1/servers/%s', $server_id)
    );

    if (!$res->{'success'}) {
        return 0, sprintf('Error connecting to PowerDNS server: %s: %s', 
                         $res->{'status'}, $res->{'content'});
    }

    return 1, 'configuration is valid';
}

# Save the DNS trust configuration file
sub _save_config {
    my ($safe_remote_user, $api_url, $api_key, $server_id, $debug) = @_;
    $safe_remote_user =~ s/\///g;

    # Make sure the config directory exists
    my $CLUSTER_ROOT     = '/var/cpanel/cluster';
    my $USER_ROOT        = $CLUSTER_ROOT . '/' . $safe_remote_user;
    my $CONFIG_ROOT      = $USER_ROOT . '/config';
    my $USER_CONFIG_FILE = $CONFIG_ROOT . '/powerdns';
    my $ROOT_CONFIG_FILE = $CLUSTER_ROOT . '/root/config/powerdns';

    foreach my $path ($CLUSTER_ROOT, $USER_ROOT, $CONFIG_ROOT) {
        if (!-e $path) {
            mkdir $path, 700;
        }
    }

    # Write the config file
    if (open my $fh, '>', $USER_CONFIG_FILE) {
        chmod 0600, $USER_CONFIG_FILE or warn "Failed to secure permissions on cluster configuration: $!";
        print {$fh} sprintf(
            "#version 2.0\napi_url=%s\napi_key=%s\nserver_id=%s\nmodule=PowerDNS\ndebug=%s\n",
            $api_url,
            $api_key,
            $server_id,
            $debug
        );
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