#!/bin/bash
#
# This script is modified from the original script from stubby: 
# https://github.com/getdnsapi/stubby/blob/develop/macos/stubby-setdns-macos.sh
#
# Original Copyright (c) 2017, Sinodun Internet Technologies Ltd, NLnet Labs
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# * Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the following disclaimer in the
#   documentation and/or other materials provided with the distribution.
# * Neither the names of the copyright holders nor the
#   names of its contributors may be used to endorse or promote products
#   derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL Verisign, Inc. BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


# Helper file to set DNS servers on macOS.
# Note - this script doesn't detect or handle network events, simply changes the
# current resolvers
# Must run as root.

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

    # download persist_dns.sh and io.github.exc4.dnspersist.plist
    echo "Downloading files..."

    curl -o /tmp/persist_dns https://raw.githubusercontent.com/exc4/macos-dns-persist/persist_dns.sh
    curl -o /tmp/$PLIST_NAME https://raw.githubusercontent.com/exc4/macos-dns-persist/io.github.exc4.dnspersist.plist

    # copy to system
    sudo cp /tmp/persist_dns /usr/local/bin/persist_dns
    sudo cp /tmp/$PLIST_NAME /Library/LaunchDaemons/$PLIST_NAME

    # set permissions
    sudo chown root:wheel /Library/LaunchDaemons/$PLIST_NAME
    sudo chmod 644 /Library/LaunchDaemons/$PLIST_NAME
    sudo chmod a+x /usr/local/bin/persist_dns

    # load the service
    echo "Loading service..."
    sudo launchctl load /Library/LaunchDaemons/$PLIST_NAME

    echo "services installed"
    echo "You can check the status of the service with: sudo launchctl list | grep $PLIST_NAME"
    echo "You can check the current dns settings with: sudo persist_dns --list"
    echo "You can reset the dns settings to default(auto from dhcp) with: sudo persist_dns --reset"
    echo "You can check the service log with: cat /var/log/persist_dns.log"
    echo "You can uninstall the service with: sudo persist_dns --uninstall"
    exit 1
}

uninstall_service() {
    echo "Uninstalling PersistDNS services"
    sudo launchctl unload /Library/LaunchDaemons/$PLIST_NAME
    sudo rm -f /Library/LaunchDaemons/$PLIST_NAME
    sudo rm -f /usr/local/bin/persist_dns
    # do you want to remove the config file?
    read -p "Do you want to remove the config file? (y/n) " REMOVE_CONFIG
    if [[ $REMOVE_CONFIG == "y" ]]; then
        sudo rm -f $CONFIG_FILE
    fi
}

list_current_dns() {
    echo "** /etc/persist_dns.conf **"
    cat /etc/persist_dns.conf
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
        networksetup -setdnsservers "$x" $servers
    done
    echo
    echo "DNS settings have been set, use --list to check"
}

### start of script

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
    echo "Config file not found. Reset to default servers. (eg. auto from DHCP)"
fi

# Install the service
if [[ $INSTALL -eq 1 ]]; then
    install_service
    exit 0
fi

if [[ $EXECUTE -eq 1 ]]; then
    set_dns_servers "$SERVERS"
    exit 0
fi
