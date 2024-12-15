# macOS Persist DNS

This repository provides a solution to persist DNS settings across all network connections on macOS using a launch service.

## Files

- `customize-dns.plist`: Launch service configuration file.
- `set_dns.sh`: Script called by the service.
- `macos_setdns.sh`: Script to set the DNS.

## How to use

To install the service, run the following command:

```bash
curl -sSL https://raw.githubusercontent.com/username/repository/main/install.sh | bash
```

## How to uninstall

```bash
curl -sSL https://raw.githubusercontent.com/username/repository/main/install.sh | bash
```



## Usage

The service will automatically call `set_dns.sh`, which in turn calls `macos_setdns.sh` to set the DNS settings.

## License

This project is licensed under the MIT License. 