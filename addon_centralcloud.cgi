#!/usr/local/cpanel/3rdparty/bin/perl

use strict;
use warnings;
use Whostmgr::HTMLInterface;
use Whostmgr::ACLS;
use Cpanel::Config::LoadCpConf;
use Cpanel::AdminBin;
use Cpanel::NameServer::Remote::CentralCloud;

Whostmgr::ACLS::init_acls();

if (!Whostmgr::ACLS::hasroot()) {
    print "Access denied\n";
    exit;
}

# Load server configuration to initialize the CentralCloud module
my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();
my $cluster_dir = '/var/cpanel/cluster';
my $config_file = '';

# Find the CentralCloud configuration file
if (opendir(my $dh, $cluster_dir)) {
    while (my $user = readdir($dh)) {
        next if $user =~ /^\./;
        next if !-d "$cluster_dir/$user";
        
        if (-f "$cluster_dir/$user/config/centralcloud") {
            $config_file = "$cluster_dir/$user/config/centralcloud";
            last;
        }
    }
    closedir($dh);
}

my %config = ();

# Parse the configuration file if found
if ($config_file && -f $config_file) {
    if (open(my $fh, '<', $config_file)) {
        while (my $line = <$fh>) {
            chomp $line;
            next if $line =~ /^#/;
            if ($line =~ /^(\w+)=(.*)$/) {
                $config{$1} = $2;
            }
        }
        close($fh);
    }
}

# Initialize the CentralCloud module with loaded config
my $centralcloud = Cpanel::NameServer::Remote::CentralCloud->new(
    'host'            => $config{'host'} || 'CentralCloud',
    'update_type'     => $config{'update_type'} || 'standalone',
    'api_url'         => $config{'api_url'} || 'https://master.ns.centralcloud.net',
    'api_key'         => $config{'api_key'} || '',
    'hostbill_url'    => $config{'hostbill_url'} || 'https://portal.centralcloud.com',
    'hostbill_api_id' => $config{'hostbill_api_id'} || '',
    'hostbill_api_key'=> $config{'hostbill_api_key'} || '',
    'log_level'       => $config{'log_level'} || 'warn',
    'output_callback' => sub { print $_[0]; },
);

Whostmgr::HTMLInterface::defheader("CentralCloud DNS Status", "DNS", "centralcloud");

# Call the status dashboard method
$centralcloud->status_dashboard('whmstatus', {}, {});

Whostmgr::HTMLInterface::footer();

1;
