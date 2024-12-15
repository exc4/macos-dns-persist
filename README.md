# macOS Persist DNS

This repository offers a solution to persist DNS settings across all network connections on macOS using a launch service.

macOS uses different DNS settings for various network connections, making it challenging to maintain consistent DNS settings when frequently connecting to new networks. However, you may prefer to use specific DNS servers across all connections, particularly when employing DNS caching tools like Dnsmasq or utilizing DNS protection services such as Stubby, Cloudflared and other tools.

This repository helps you set the same DNS servers for all network connections and persist these settings by using a launch service. The service executes the settings periodically and upon network changes to ensure the DNS settings remain consistent.

## Files

-  `io.github.exc4.dnspersist.plist`: Launch service configuration file.
-  `persist_dns.sh`: Shell command script.

## How to Use

To install the service, run the following commands:

```bash
git clone https://github.com/exc4/macos-dns-persist.git
cd macos-dns-persist

# Set the DNS configuration for persistence.
# You can specify multiple DNS servers separated by spaces.
sudo echo "8.8.8.8 8.8.4.4" > /etc/persist_dns.conf

./persist_dns.sh --install
```

After installation, the script applies the DNS settings immediately and continues to persist the setting periodically and whenever the network changes. 
## How to Uninstall

```bash
persist_dns --uninstall
```

## How to Configure DNS Persistence

To set the DNS servers, edit the `/etc/persist_dns.conf` file. 
```
echo "127.0.0.1 ::1" > /etc/persist_dns.conf     # use local DNS server, ensure there is one running on the system
                                                 # you can choose dnsmasq, stubby, cloudflared and etc. 
                                                 
echo "8.8.8.8 8.8.4.4" > /etc/persist_dns.conf   # use public DNS servers

echo "DEFAULT" > /etc/persist_dns.conf           # use default DNS servers obtained from DHCP
```
After editing the file, run the following command to apply the changes:

```bash
sudo persist_dns
```

The default time interval for the periodic execution is 5 minutes. You can adjust this interval by editing the `/Library/LaunchDaemons/io.github.exc4.dnspersist.plist` file, and changing the `StartInterval` value.

After editing the file, run the following command to apply the changes:

```bash
sudo launchctl unload /Library/LaunchDaemons/io.github.exc4.dnspersist.plist
sudo launchctl load /Library/LaunchDaemons/io.github.exc4.dnspersist.plist
```

## License

This project is licensed under the MIT License.

## Copyright

This script is inspired by the original script from stubby: [stubby-setdns-macos.sh](https://github.com/getdnsapi/stubby/blob/develop/macos/stubby-setdns-macos.sh).

Original Copyright (c) 2017, Sinodun Internet Technologies Ltd, NLnet Labs. All rights reserved.

The script has been modified to function as a service to persist DNS settings on macOS.
