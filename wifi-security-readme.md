# WiFi Security Scripts

A collection of scripts to enhance security when using public WiFi networks.

## Overview

These scripts help you:
1. Secure your system when connecting to public WiFi
2. Monitor for suspicious network activity
3. Safely disconnect and restore settings when done

## Scripts

### 1. wifi-secure.sh

This script enhances your security when connecting to public WiFi networks.

**Features:**
- Creates backups of your original settings
- Configures firewall with balanced security settings
- Sets up secure DNS servers (Cloudflare and Google)
- Checks and optionally disables sharing services
- Verifies VPN status
- Checks for system updates
- Provides easy restoration of original settings

**Usage:**
```bash
# Interactive menu
sudo ~/.scripts/wifi-secure.sh

# Apply security measures directly
sudo ~/.scripts/wifi-secure.sh on

# Restore settings from latest backup
sudo ~/.scripts/wifi-secure.sh off

# Show help
sudo ~/.scripts/wifi-secure.sh help
```

The interactive menu provides options to:
- Apply security measures
- Restore settings from a backup
- Quick restore from latest backup
- Exit

All changes can be reversed using the restore options.

### 2. wifi-monitor.sh

This script monitors your network connections for suspicious activity.

**Features:**
- Provides detailed network information (IP, MAC, gateway, DNS, signal strength)
- Displays your public IP address and checks if it's behind a proxy/NAT
- Detects sudden increases in network connections
- Monitors for ARP spoofing attacks
- Checks for suspicious open ports and identifies the processes using them
- Provides detailed process information for open ports (user, command line)
- Detects potential DNS leaks and unusual DNS behavior
- Checks for DNS hijacking by validating resolved IPs against known ranges
- Investigates unusual connections to high ports or suspicious IP ranges
- Identifies processes with abnormally high connection counts
- Displays a network summary with active connections and top processes
- Monitors network traffic volume and alerts on unusual spikes
- Tracks connection history across different networks
- Provides whois information for suspicious remote IPs
- Shows CPU usage for network-intensive processes
- Identifies known services on remote ports
- Filters out common Unix domain sockets to reduce false positives
- Displays system load averages
- Offers a quick scan mode for faster results
- Logs all activity for review
- Provides desktop notifications for security alerts
- Offers low resource usage mode for longer monitoring sessions
- Customizable known networks list for tailored security

**Usage:**
```bash
sudo ~/.scripts/wifi-monitor.sh
```

The script will present a menu with options to:
- Start monitoring in normal mode
- Start monitoring in low resource usage mode
- Run a quick scan (one-time check)
- View connection history
- View the current log file
- Exit

Press Ctrl+C to stop monitoring.

### 3. wifi-disconnect.sh

This script helps you safely disconnect from public WiFi networks.

**Features:**
- Optionally disconnects from WiFi
- Resets DNS settings to DHCP
- Clears network caches
- Resets firewall settings
- Optionally re-enables sharing services
- Can restore settings from backup

**Usage:**
```bash
# Interactive menu
sudo ~/.scripts/wifi-disconnect.sh

# Perform disconnect and reset directly
sudo ~/.scripts/wifi-disconnect.sh disconnect

# Restore settings from latest backup
sudo ~/.scripts/wifi-disconnect.sh restore

# Show help
sudo ~/.scripts/wifi-disconnect.sh help
```

The interactive menu provides options to:
- Perform disconnect and reset (with prompts for each step)
- Restore settings from backup
- Quick restore from latest backup
- Exit

## Recommended Workflow

1. When connecting to public WiFi:
   ```bash
   sudo ~/.scripts/wifi-secure.sh on
   ```
   Or use the interactive menu and select option 1.

2. While using public WiFi:
   ```bash
   sudo ~/.scripts/wifi-monitor.sh
   ```
   Select option 1 or 2 to start monitoring.

3. When finished with public WiFi:
   ```bash
   sudo ~/.scripts/wifi-disconnect.sh disconnect
   ```
   Or use the interactive menu and select option 1.

4. To restore original settings:
   ```bash
   sudo ~/.scripts/wifi-secure.sh off
   ```
   Or use the interactive menu and select option 3 for quick restore.

## Security Features

- **Backup System**: All settings are backed up before changes are made
- **Integrity Verification**: Backups are verified before restoration
- **Secure Permissions**: Backup files are created with secure permissions (chmod 600)
- **Latest Backup Symlink**: Easy access to the most recent backup
- **Command Line Options**: Quick access to common operations
- **Balanced Security**: Security measures that don't disrupt normal operations
- **Error Handling**: Robust error handling to prevent script failures
- **Fallback Options**: Default values when system information can't be determined

## Customization

- **Known Networks**: Edit the `KNOWN_NETWORKS` array in wifi-monitor.sh to add your trusted networks
- **Monitoring Intervals**: Adjust the interval constants in wifi-monitor.sh to change monitoring frequency
- **DNS Servers**: Modify the DNS servers in wifi-secure.sh if you prefer alternatives to Cloudflare and Google

## Notes

- All scripts create backups of your original settings
- All changes can be easily reversed
- Scripts are designed to be non-disruptive to normal operations
- Backups are stored in ~/.wifi-secure-backups
- Logs are stored in ~/.logs 