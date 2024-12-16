#!/bin/bash
#
# This script is inspired by the original script from stubby:
# https://github.com/getdnsapi/stubby/blob/develop/macos/stubby-setdns-macos.sh
# Original Copyright (c) 2017, Sinodun Internet Technologies Ltd, NLnet Labs. All rights reserved.
# The script has been modified to function as a service to persist DNS settings on macOS.


# Helper file to set DNS resolvers on macOS.
# Note - this script doesn't detect or handle network events, simply changes the
# current resolvers
# Must run as root.

set -e

### define functions

usage () {
    echo
    echo "Update the system DNS resolvers used for all DNS queries on macOS."
    echo
    echo "This must be run as root."
    echo
    echo "Config file at: $CONFIG_FILE"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Supported options:"
    echo
    echo "  -l, --list        List the current DNS settings for all interfaces"
    echo
    echo "  --install         Install as a system service to persist DNS settings."
    echo "                    The service will automatically set the DNS servers on all interfaces at specified time intervals and monitor for network changes."
    echo
    echo "  --uninstall       Uninstall the system service to stop persisting DNS settings."
    echo
    echo "  -h, --help        Show this help."
}

install_service() {
    # copy to system
    cp -f ./persist_dns.sh /usr/local/bin/persist_dns || { echo "Failed to copy persist_dns.sh"; exit 1; }
    cp -f ./$PLIST_NAME /Library/LaunchDaemons/$PLIST_NAME || { echo "Failed to copy $PLIST_NAME"; exit 1; }

    rm -f /tmp/persist_dns
    rm -f /tmp/$PLIST_NAME

    # set permissions
    chown root:wheel /Library/LaunchDaemons/$PLIST_NAME || { echo "Failed to change ownership of $PLIST_NAME"; exit 1; }
    chmod 644 /Library/LaunchDaemons/$PLIST_NAME || { echo "Failed to set permissions for $PLIST_NAME"; exit 1; }
    chmod a+x /usr/local/bin/persist_dns || { echo "Failed to set execute permission for persist_dns"; exit 1; }

    # load the service
    launchctl load /Library/LaunchDaemons/$PLIST_NAME || { echo "Failed to load service"; exit 1; }

    echo "========================================"
    echo "✅ Installation Successful!"
    echo "========================================"
    echo
    echo "The DNS settings have been successfully persisted from the configuration file: ${CONFIG_FILE}"
    echo "Current DNS servers: ${CONFIG_CONTENT}"
    echo
    echo "The service has been installed and is now running as a system service to persist DNS settings."
    echo
    echo "🔍 To check the status of the service, use:"
    echo "    sudo launchctl list | grep io.github.exc4.dnspersist"
    echo
    echo "    should return: '- 0 io.github.exc4.dnspersist' for successful execution"
    echo
    echo "🔧 To view the current DNS settings, use:"
    echo "    persist_dns --list"
    echo
    echo "📜 To view the service log, use:"
    echo "    cat /var/log/persist_dns.log"
    echo
    echo "🗑️ To uninstall the service, use:"
    echo "    sudo persist_dns --uninstall"
    echo
    echo "========================================"

    exit 0
}

uninstall_service() {
    echo "========================================"
    echo "🗑️ Uninstalling service"
    echo "========================================"

    # do you want to reset to default?
    read -p "🔄 Do you want reset to default DNS servers? (y/n) " RESET_DEFAULT
    read -p "🗑️ Do you want to remove the config file? (y/n) " REMOVE_CONFIG

    if [[ $RESET_DEFAULT == "y" ]]; then
        sudo set_dns_servers "empty"
    fi

    if [[ $REMOVE_CONFIG == "y" ]]; then
        sudo rm -f $CONFIG_FILE
    fi

    if [[ -f /Library/LaunchDaemons/$PLIST_NAME ]]; then
        sudo launchctl unload /Library/LaunchDaemons/$PLIST_NAME
        sudo rm -f /Library/LaunchDaemons/$PLIST_NAME
    fi

    if [[ -f /usr/local/bin/persist_dns ]]; then
        sudo rm -f /usr/local/bin/persist_dns
    fi

    if [[ -f /var/log/persist_dns.log ]]; then
        sudo rm -f /var/log/persist_dns.log
    fi

    echo "========================================"
    echo "✅ Uninstallation Successful!"
    echo "========================================"
}

list_current_dns() {
    echo "** /etc/persist_dns.conf **"
    if [[ -f $CONFIG_FILE ]]; then 
        cat $CONFIG_FILE
    else
        echo "Config file not found. Using default servers. (eg. auto from DHCP)"
    fi
    echo
    echo "** Current DNS settings **"
    echo
    networksetup -listallnetworkservices 2>/dev/null | grep -v '\*' | while read -r x ; do
        RESULT=$(networksetup -getdnsservers "$x")
        RESULT=$(echo $RESULT)
        printf '%-30s %s\n' "$x:" "$RESULT"
    done
    echo
    echo "** End of current DNS settings **"
    echo "** Showing /etc/resolv.conf **"
    echo
    cat /etc/resolv.conf
    echo
    echo "** End of /etc/resolv.conf **"
}


# Set the DNS settings via networksetup
set_dns_servers() {
    local servers="$1"
    networksetup -listallnetworkservices 2>/dev/null | grep -v '\*' | while read -r x ; do
        sudo networksetup -setdnsservers "$x" $servers
    done
    echo
    echo "🔄 DNS resolvers have been set, use --list to check"
    echo
}

### start of script

# check the log file size
LOG_FILE="/var/log/persist_dns.log"
if [[ -f $LOG_FILE ]]; then
    LOG_FILE_SIZE=$(stat -f%z $LOG_FILE)
    if [[ $LOG_FILE_SIZE -gt 500000 ]]; then
        sudo truncate -s 0 $LOG_FILE
        echo "🗑️ Log file is too large. Cleared log file."
    fi
fi

RESET=0
LIST=0
INSTALL=0
UNINSTALL=0
EXECUTE=0
CONFIG_FILE="/etc/persist_dns.conf"
PLIST_NAME="io.github.exc4.dnspersist.plist"
OS_X=$(uname -a | grep -c 'Darwin')

# no args, set
if [ $# -eq 0 ]; then
    EXECUTE=1
else
    case "$1" in
        "-l"|"--list") 
            LIST=1 
            ;;
        "--install") 
            INSTALL=1 
            ;;
        "--uninstall") 
            UNINSTALL=1 
            ;;
        "-h"|"--help")
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
fi

# List current DNS settings
if [[ $LIST -eq 1 ]]; then
    list_current_dns
    exit 0
fi

if [[ $OS_X -eq 0 ]]; then
    echo "❌ Sorry - This script only works on macOS and you are on a different OS."
    exit 1
fi

if [ $EUID -ne 0 ]; then
    echo "❌ Must be root to update system resolvers. Retry with sudo."
    exit 1
fi

# Uninstall the service
if [[ $UNINSTALL -eq 1 ]]; then
    uninstall_service
    exit 0
fi

# Load DNS servers from config file
echo "========================================"
echo "🔍 Checking Configuration File"
echo "========================================"
echo

if [[ -f $CONFIG_FILE ]]; then
    CONFIG_CONTENT=$(cat $CONFIG_FILE | tr '\n' ' ')
    if [[ $CONFIG_CONTENT == "DEFAULT" ]]; then
        SERVERS="empty"
    else
        SERVERS=$CONFIG_CONTENT
    fi
    echo "✅ Configuration file found at: $CONFIG_FILE"
    echo "   DNS servers will be persisted from the configuration: $CONFIG_CONTENT"
else
    echo "❌ Configuration file not found!"
    echo "   Please create a configuration file at: $CONFIG_FILE"
    echo
    echo "   Example if using localhost:"
    echo "      echo '127.0.0.1 ::1' | sudo tee $CONFIG_FILE"
    echo
    echo "   Example if using Cloudflare:"
    echo "      echo '1.1.1.1 1.0.0.1' | sudo tee $CONFIG_FILE"
    echo
    echo "   Example if using Default from DHCP:"
    echo "      echo 'DEFAULT' | sudo tee $CONFIG_FILE"
    exit 1
fi

echo

# Install the service
if [[ $INSTALL -eq 1 ]]; then
    install_service
    exit 0
fi

if [[ $EXECUTE -eq 1 ]]; then
    set_dns_servers "$SERVERS"
    exit 0
fi
