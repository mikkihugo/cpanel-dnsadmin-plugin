# CentralCloud DNS Clustering Plugin for cPanel

This plugin allows cPanel servers to integrate with CentralCloud's PowerDNS service, enabling DNS zone synchronization between cPanel and PowerDNS.

## Features

- Integrates cPanel DNS Clustering with PowerDNS API
- Manages DNS zones on remote PowerDNS servers
- Supports DNSSEC via HostBill API integration
- Filters operations to only manage domains hosted on the cPanel server
- Provides dry-run mode for safe testing before making real changes
- Comprehensive logging for debugging and tracking operations
- Health monitoring with email notifications
- Auto-repair capability for DNS zone discrepancies
- Status dashboard for monitoring the integration
- Development mode for restricting operations to test domains only

## Accessing the Status Dashboard

The plugin includes a web-based status dashboard that provides detailed information about the integration:

1. **Through WHM Plugin Section**:
   - Log in to WHM
   - Navigate to the "Plugins" section
   - Click on "CentralCloud DNS Status"

2. **Direct Access**:
   - Access WHM
   - Go to: `https://your-server:2087/cgi/addon_centralcloud.cgi`

The dashboard shows:
- PowerDNS and HostBill API status
- Current configuration settings
- Zone statistics
- Recent zone information
- Auto-repair activity

This dashboard is automatically installed by the installation script and provides a convenient way to monitor the health and status of your DNS integration.

## Requirements

- cPanel server (tested with cPanel & WHM 11.xx+)
- PowerDNS server with API access
- HostBill with DNS management module for DNSSEC support
- Perl 5.10+
- Required Perl modules (included with cPanel):
  - Cpanel::JSON::XS
  - HTTP::Tiny
  - Cpanel::Logger
  - List::MoreUtils

## Installation

### Automated Installation

1. Download the plugin package
2. Extract the package
3. Run the installation script:

```bash
chmod +x install.sh
./install.sh
```

### Manual Installation

1. Copy the module files to the appropriate directories:
   - `lib/Cpanel/NameServer/Remote/CentralCloud.pm` → `/usr/local/cpanel/Cpanel/NameServer/Remote/`
   - `lib/Cpanel/NameServer/Remote/CentralCloud/API.pm` → `/usr/local/cpanel/Cpanel/NameServer/Remote/CentralCloud/`
   - `lib/Cpanel/NameServer/Setup/Remote/CentralCloud.pm` → `/usr/local/cpanel/Cpanel/NameServer/Setup/Remote/`

2. Set file permissions:
   - `chmod 644 /usr/local/cpanel/Cpanel/NameServer/Remote/CentralCloud.pm`
   - `chmod 644 /usr/local/cpanel/Cpanel/NameServer/Remote/CentralCloud/API.pm`
   - `chmod 644 /usr/local/cpanel/Cpanel/NameServer/Setup/Remote/CentralCloud.pm`

3. Create log file:
   - `touch /var/log/centralcloud-plugin.log`
   - `chmod 644 /var/log/centralcloud-plugin.log`
   - `chown nobody:nobody /var/log/centralcloud-plugin.log`

## Configuration

1. Log in to WHM
2. Go to "Clusters" > "Configure Cluster"
3. Click "Add a new server to the cluster"
4. Select "CentralCloud" as the DNS server type
5. Enter the following details:
   - PowerDNS API URL (e.g., `https://master.ns.centralcloud.net`)
   - PowerDNS API Key
   - HostBill URL (e.g., `https://portal.centralcloud.com`)
   - HostBill API ID & API Key
   - Log Level (Select from: error, warn, info, debug)
   - Log File Path
   - DNS Record Settings (TTL, SOA refresh, retry, expire, etc.)

6. Select the server type:
   - **standalone** - Dry run mode (no changes made to PowerDNS/HostBill)
   - **writeonly** - Write mode (changes made to PowerDNS/HostBill)

## Operation

The plugin operates in one of two modes:

### Dry Run Mode (default)

When the server type is set to "standalone", the plugin operates in dry run mode:
- All operations are logged
- No actual changes are made to PowerDNS or HostBill
- Responses indicate what would have happened
- Useful for testing and verification

### Write Mode

When the server type is set to "writeonly", the plugin makes actual changes:
- Real zone operations on PowerDNS
- Real DNSSEC operations via HostBill
- Full functionality in production

## Logging

The plugin logs all operations to the configured log file (default: `/var/log/centralcloud-plugin.log`).

Log levels:
- **error** - Only serious errors
- **warn** - Warnings and errors
- **info** - General operational information
- **debug** - Detailed debugging information

## Troubleshooting

### Common Issues

1. **Permission denied errors**:
   - Ensure the log file is writable
   - Check file permissions on module files

2. **API connection errors**:
   - Verify API URL is correct
   - Check API key is valid
   - Test network connectivity to API endpoints

3. **No zones showing in cPanel**:
   - Check if domains exist on both cPanel and PowerDNS
   - Verify filtering is working correctly
   - Look for errors in the log file

### Debug Mode

For detailed troubleshooting:
1. Set log level to "debug" in the configuration
2. Check the log file for detailed messages
3. Look for [DEBUG] prefixed entries

## License

This plugin is licensed under the MIT License. See LICENSE file for more information.

## Support

For support with this plugin, please contact CentralCloud support.
