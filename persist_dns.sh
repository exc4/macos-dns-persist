#!/bin/bash
#
# This script is inspired by the original script from stubby:
# https://github.com/getdnsapi/stubby/blob/develop/macos/stubby-setdns-macos.sh
# Original Copyright (c) 2017, Sinodun Internet Technologies Ltd, NLnet Labs. All rights reserved.
# The script has been modified to function as a service to persist DNS settings on macOS.


# Helper file to set DNS servers on macOS.
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
    echo "  -r, --reset       Set DNS resolvers to default (e.g. auto from DHCP)."
    echo "                    If you have installed the service, this will also set the config file to use the default servers."
    echo
    echo "  --install         Install as a system service to persist DNS settings."
    echo "                    The service will automatically set the DNS servers on all interfaces at specified time intervals and monitor for network changes."
    echo
    echo "  --uninstall       Uninstall the system service to stop persisting DNS settings."
    echo
    echo "  -h, --help        Show this help."
}

install_service() {
    echo "Installing as a system service to persist DNS settings"

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

    echo "Installed"
    echo
    echo "You can check the status of the service with:"
    echo "    sudo launchctl list | grep io.github.exc4.dnspersist"
    echo
    echo "You can check the current dns settings with:"
    echo "    persist_dns --list"
    echo "status code 0 means success executed. The dns settings will be executed at regular intervals and will also be triggered by network changes."
    echo
    echo "You can check the service log with:"
    echo "    cat /var/log/persist_dns.log"
    echo
    echo "You can uninstall the service with:"
    echo "    sudo persist_dns --uninstall"
    exit 1
}

uninstall_service() {
    echo "Uninstalling PersistDNS services"
    sudo launchctl unload /Library/LaunchDaemons/$PLIST_NAME
    sudo rm -f /Library/LaunchDaemons/$PLIST_NAME
    sudo rm -f /usr/local/bin/persist_dns
    sudo rm -f /var/log/persist_dns.log
    # do you want to remove the config file?
    read -p "Do you want to remove the config file? (y/n) " REMOVE_CONFIG
    if [[ $REMOVE_CONFIG == "y" ]]; then
        sudo rm -f $CONFIG_FILE
    fi
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
    echo "DNS settings have been set, use --list to check"
}

### start of script

# check the log file size
LOG_FILE="/var/log/persist_dns.log"
LOG_FILE_SIZE=$(stat -f%z $LOG_FILE)
if [[ $LOG_FILE_SIZE -gt 1000000 ]]; then
    sudo truncate -s 0 $LOG_FILE
    echo "Log file is too large. Cleared log file."
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
        "-r"|"--reset") 
            RESET=1 
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
    echo "Sorry - This script only works on macOS and you are on a different OS."
    exit 1
fi

if [ $EUID -ne 0 ]; then
    echo "Must be root to update system resolvers. Retry with sudo."
    exit 1
fi

# Reset DNS settings to default
if [[ $RESET -eq 1 ]]; then
    echo "Resetting DNS settings to default"
    set_dns_servers "empty"
    echo
    echo "This setting is temporary. You need set DEFAULT in $CONFIG_FILE to persist DNS settings."
    exit 0
fi


# Uninstall the service
if [[ $UNINSTALL -eq 1 ]]; then
    uninstall_service
    exit 0
fi

# Load DNS servers from config file
echo "Checking config file at: $CONFIG_FILE"
echo
if [[ -f $CONFIG_FILE ]]; then
    CONFIG_CONTENT=$(cat $CONFIG_FILE | tr '\n' ' ')
    if [[ $CONFIG_CONTENT == "DEFAULT" ]]; then
        SERVERS="empty"
    else
        SERVERS=$CONFIG_CONTENT
    fi
    echo "DNS servers will be persisted from config: $CONFIG_CONTENT"

else
    SERVERS="empty"
    echo "Config file not found. Using default servers. (eg. auto from DHCP)"
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
