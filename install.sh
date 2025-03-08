#!/bin/bash
#
# Install script for CentralCloud cPanel DNS Clustering Plugin
# 
# This script will install the CentralCloud DNS clustering plugin for cPanel
# It requires root privileges to run

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories
CPANEL_ROOT="/usr/local/cpanel"
CPANEL_LIB="$CPANEL_ROOT/Cpanel"
MODULE_DIR="$CPANEL_LIB/NameServer/Remote"
API_DIR="$MODULE_DIR/CentralCloud"
SETUP_DIR="$CPANEL_LIB/NameServer/Setup/Remote"
WHM_CGI_DIR="$CPANEL_ROOT/whostmgr/docroot/cgi"
WHM_ADDON_DIR="$CPANEL_ROOT/whostmgr/docroot/cgi/addons"
WHM_ICONS_DIR="$CPANEL_ROOT/whostmgr/docroot/addon_plugins"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

echo -e "${BLUE}CentralCloud DNS Clustering Plugin Installer${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Function to display progress messages
progress() {
  echo -e "${GREEN}[*]${NC} $1"
}

# Function to display warning messages
warning() {
  echo -e "${YELLOW}[!]${NC} $1"
}

# Function to display error messages
error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Check if cPanel is installed
if [ ! -d "$CPANEL_LIB" ]; then
  error "cPanel installation not found at $CPANEL_LIB"
  exit 1
fi

# Create required directories
progress "Creating required directories..."
mkdir -p "$MODULE_DIR"
mkdir -p "$API_DIR"
mkdir -p "$SETUP_DIR"
mkdir -p "$WHM_ADDON_DIR"
mkdir -p "$WHM_ICONS_DIR"

# Install the module files
progress "Installing module files..."

# Check if files exist and create backup if they do
if [ -f "$MODULE_DIR/CentralCloud.pm" ]; then
  warning "Found existing CentralCloud module, creating backup..."
  cp "$MODULE_DIR/CentralCloud.pm" "$MODULE_DIR/CentralCloud.pm.bak.$(date +%s)"
fi

if [ -f "$API_DIR/API.pm" ]; then
  warning "Found existing CentralCloud API module, creating backup..."
  cp "$API_DIR/API.pm" "$API_DIR/API.pm.bak.$(date +%s)"
fi

if [ -f "$SETUP_DIR/CentralCloud.pm" ]; then
  warning "Found existing CentralCloud setup module, creating backup..."
  cp "$SETUP_DIR/CentralCloud.pm" "$SETUP_DIR/CentralCloud.pm.bak.$(date +%s)"
fi

if [ -f "$WHM_CGI_DIR/addon_centralcloud.cgi" ]; then
  warning "Found existing WHM integration script, creating backup..."
  cp "$WHM_CGI_DIR/addon_centralcloud.cgi" "$WHM_CGI_DIR/addon_centralcloud.cgi.bak.$(date +%s)"
fi

# Copy module files from the install package
if [ -f "./lib/Cpanel/NameServer/Remote/CentralCloud.pm" ]; then
  progress "Installing main module from package..."
  cp "./lib/Cpanel/NameServer/Remote/CentralCloud.pm" "$MODULE_DIR/CentralCloud.pm"
else
  error "Main module file not found in package!"
  exit 1
fi

if [ -f "./lib/Cpanel/NameServer/Remote/CentralCloud/API.pm" ]; then
  progress "Installing API module from package..."
  cp "./lib/Cpanel/NameServer/Remote/CentralCloud/API.pm" "$API_DIR/API.pm"
else
  error "API module file not found in package!"
  exit 1
fi

if [ -f "./lib/Cpanel/NameServer/Setup/Remote/CentralCloud.pm" ]; then
  progress "Installing setup module from package..."
  cp "./lib/Cpanel/NameServer/Setup/Remote/CentralCloud.pm" "$SETUP_DIR/CentralCloud.pm"
else
  error "Setup module file not found in package!"
  exit 1
fi

# Install WHM integration files
progress "Installing WHM integration files..."

if [ -f "./addon_centralcloud.cgi" ]; then
  cp "./addon_centralcloud.cgi" "$WHM_CGI_DIR/addon_centralcloud.cgi"
  chmod 755 "$WHM_CGI_DIR/addon_centralcloud.cgi"
else
  error "WHM integration script not found in package!"
  exit 1
fi

if [ -f "./centralcloud.conf" ]; then
  cp "./centralcloud.conf" "$WHM_ADDON_DIR/centralcloud.conf"
else
  error "WHM plugin configuration not found in package!"
  exit 1
fi

if [ -f "./centralcloud.png" ]; then
  cp "./centralcloud.png" "$WHM_ICONS_DIR/centralcloud.png"
elif [ -f "./centralcloud.svg" ]; then
  progress "Found SVG icon, converting to PNG..."
  # Try to convert SVG to PNG if ImageMagick is available
  if command -v convert >/dev/null 2>&1; then
    convert -background none -resize 64x64 "./centralcloud.svg" "$WHM_ICONS_DIR/centralcloud.png"
  else
    warning "ImageMagick not found, cannot convert SVG to PNG"
    warning "Using default icon instead..."
    # Download a default icon
    curl -s "https://raw.githubusercontent.com/powerdns/pdns/master/docs/logos/powerdns-logo-500px.png" > "$WHM_ICONS_DIR/centralcloud.png"
  fi
else
  warning "Icon file not found, using default..."
  # Create a default icon if not provided
  curl -s "https://raw.githubusercontent.com/powerdns/pdns/master/docs/logos/powerdns-logo-500px.png" > "$WHM_ICONS_DIR/centralcloud.png"
fi

# Set permissions
progress "Setting file permissions..."
chmod 644 "$MODULE_DIR/CentralCloud.pm"
chmod 644 "$API_DIR/API.pm"
chmod 644 "$SETUP_DIR/CentralCloud.pm"
chmod 644 "$WHM_ADDON_DIR/centralcloud.conf"
chmod 644 "$WHM_ICONS_DIR/centralcloud.png"

# Create log file
LOG_FILE="/var/log/centralcloud-plugin.log"
progress "Creating log file at $LOG_FILE"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
chown nobody:nobody "$LOG_FILE"

# Register the plugin with WHM if needed
progress "Registering plugin with WHM..."
if [ -x "$CPANEL_ROOT/bin/manage_hooks" ]; then
    $CPANEL_ROOT/bin/manage_hooks add module CentralCloud
fi

# Check if all files were installed correctly
if [ -f "$MODULE_DIR/CentralCloud.pm" ] && [ -f "$API_DIR/API.pm" ] && [ -f "$SETUP_DIR/CentralCloud.pm" ] && [ -f "$WHM_CGI_DIR/addon_centralcloud.cgi" ]; then
  progress "Checking installation..."
  grep -q "package Cpanel::NameServer::Remote::CentralCloud;" "$MODULE_DIR/CentralCloud.pm"
  MAIN_CHECK=$?
  grep -q "package Cpanel::NameServer::Remote::CentralCloud::API;" "$API_DIR/API.pm"
  API_CHECK=$?
  grep -q "package Cpanel::NameServer::Setup::Remote::CentralCloud;" "$SETUP_DIR/CentralCloud.pm"
  SETUP_CHECK=$?
  
  if [ $MAIN_CHECK -eq 0 ] && [ $API_CHECK -eq 0 ] && [ $SETUP_CHECK -eq 0 ]; then
    echo
    echo -e "${GREEN}CentralCloud DNS Clustering Plugin successfully installed!${NC}"
    echo
    echo -e "To configure the plugin:"
    echo -e "1. Log in to WHM"
    echo -e "2. Go to 'Clusters' > 'Configure Cluster'"
    echo -e "3. Click 'Add a new server to the cluster'"
    echo -e "4. Select 'CentralCloud' as the DNS server type"
    echo -e "5. Enter your API and HostBill credentials"
    echo -e "6. Choose 'standalone' for dry-run mode or 'writeonly' to make real changes"
    echo
    echo -e "To access the status dashboard:"
    echo -e "1. Log in to WHM"
    echo -e "2. Go to 'Plugins' section"
    echo -e "3. Click on 'CentralCloud DNS Status'"
    echo
    echo -e "Log file location: ${YELLOW}$LOG_FILE${NC}"
    echo
  else
    error "Installation verification failed. The files may be corrupted."
    exit 1
  fi
else
  error "Installation failed. Some files are missing."
  exit 1
fi

# Done
exit 0
