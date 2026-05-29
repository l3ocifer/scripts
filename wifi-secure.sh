#!/bin/bash
#
# wifi-secure.sh - A script to enhance security when connecting to public WiFi
#
# This script configures firewall settings, enables stealth mode,
# and applies other security measures for safer public WiFi usage.

# Exit on error
set -e

# Set colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Backup directory for original settings
BACKUP_DIR="$HOME/.wifi-secure-backups"
BACKUP_FILE="$BACKUP_DIR/settings-$(date +%Y%m%d-%H%M%S).bak"

# Print banner
echo -e "${BLUE}=========================================================${NC}"
echo -e "${BLUE}           Public WiFi Security Enhancer                 ${NC}"
echo -e "${BLUE}=========================================================${NC}"

# Check if script is run with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this script with sudo privileges${NC}"
    exit 1
fi

# Function to print status messages
print_status() {
    local status=$1
    local message=$2
    
    if [ "$status" -eq 0 ]; then
        echo -e "[ ${GREEN}OK${NC} ] $message"
    else
        echo -e "[${RED}FAIL${NC}] $message"
    fi
}

# Create backup directory
create_backup_dir() {
    mkdir -p "$BACKUP_DIR"
    echo -e "\n${YELLOW}Creating backup of current settings...${NC}"
    
    # Create backup file with timestamp
    touch "$BACKUP_FILE"
    chmod 600 "$BACKUP_FILE"  # Secure the backup file
    
    # Get current network interface
    INTERFACE=$(networksetup -listallhardwareports | grep -A 1 "Wi-Fi" | grep "Device" | awk '{print $2}')
    
    if [ -z "$INTERFACE" ]; then
        echo -e "${RED}Could not determine WiFi interface. Using default 'en0'.${NC}"
        INTERFACE="en0"
    fi
    
    # Backup current DNS settings
    echo "# DNS Settings Backup" >> "$BACKUP_FILE"
    networksetup -getdnsservers "$INTERFACE" >> "$BACKUP_FILE"
    
    # Backup firewall settings
    echo "# Firewall Settings Backup" >> "$BACKUP_FILE"
    echo "FIREWALL_STATE=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | grep -i "enabled" | awk '{print $3}')" >> "$BACKUP_FILE"
    echo "STEALTH_MODE=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode | grep -i "enabled" | awk '{print $3}')" >> "$BACKUP_FILE"
    echo "BLOCK_ALL=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getblockall | grep -i "enabled" | awk '{print $3}')" >> "$BACKUP_FILE"
    
    # Backup sharing settings
    echo "# Sharing Settings Backup" >> "$BACKUP_FILE"
    echo "SCREEN_SHARING=$(launchctl list | grep -c "com.apple.screensharing")" >> "$BACKUP_FILE"
    echo "FILE_SHARING_AFP=$(launchctl list | grep -c "com.apple.AppleFileServer")" >> "$BACKUP_FILE"
    echo "FILE_SHARING_SMB=$(launchctl list | grep -c "com.apple.smbd")" >> "$BACKUP_FILE"
    echo "REMOTE_LOGIN=$(systemsetup -getremotelogin | awk '{print $3}')" >> "$BACKUP_FILE"
    
    # Save timestamp for verification
    echo "BACKUP_TIMESTAMP=$(date)" >> "$BACKUP_FILE"
    
    print_status 0 "Backed up current settings to $BACKUP_FILE"
    
    # Create a symlink to the latest backup for easy access
    ln -sf "$BACKUP_FILE" "$BACKUP_DIR/latest.bak"
    print_status $? "Created symlink to latest backup"
}

# Enable macOS firewall with less restrictive settings
enable_firewall() {
    echo -e "\n${YELLOW}Configuring macOS firewall...${NC}"
    
    # Turn on firewall
    /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
    print_status $? "Enabled firewall"
    
    # Enable stealth mode (don't respond to ICMP ping requests)
    /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
    print_status $? "Enabled stealth mode"
    
    # Instead of blocking all connections, we'll use a more balanced approach
    # that allows signed applications to receive connections
    /usr/libexec/ApplicationFirewall/socketfilterfw --setallowsigned on
    print_status $? "Allowing signed applications to receive connections"
    
    # Allow signed applications to be modified by installer
    /usr/libexec/ApplicationFirewall/socketfilterfw --setallowsignedapp on
    print_status $? "Allowing signed applications to be modified by installer"
    
    echo -e "${YELLOW}Note: Not blocking all incoming connections to maintain compatibility with normal operations${NC}"
    echo -e "${YELLOW}You can run 'sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on' manually if needed${NC}"
}

# Configure DNS to use secure DNS servers
configure_dns() {
    echo -e "\n${YELLOW}Configuring secure DNS servers...${NC}"
    
    # Get current network interface
    INTERFACE=$(networksetup -listallhardwareports | grep -A 1 "Wi-Fi" | grep "Device" | awk '{print $2}')
    
    if [ -z "$INTERFACE" ]; then
        echo -e "${RED}Could not determine WiFi interface. Using default 'en0'.${NC}"
        INTERFACE="en0"
    fi
    
    # Set DNS to Cloudflare and Google (secure DNS providers)
    networksetup -setdnsservers "$INTERFACE" 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4
    print_status $? "Set DNS servers to Cloudflare and Google DNS"
    
    # Flush DNS cache
    dscacheutil -flushcache
    killall -HUP mDNSResponder 2>/dev/null || true
    print_status $? "Flushed DNS cache"
}

# Check sharing services and offer to disable them
check_sharing() {
    echo -e "\n${YELLOW}Checking sharing services...${NC}"
    
    # Check screen sharing
    if launchctl list | grep -q "com.apple.screensharing"; then
        echo -e "${YELLOW}Screen sharing is currently enabled.${NC}"
        echo -e "${YELLOW}Would you like to disable screen sharing? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            launchctl unload -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
            print_status $? "Disabled screen sharing"
        else
            echo -e "${GREEN}Keeping screen sharing enabled${NC}"
        fi
    else
        echo -e "${GREEN}Screen sharing is already disabled${NC}"
    fi
    
    # Check file sharing
    if launchctl list | grep -q "com.apple.AppleFileServer" || launchctl list | grep -q "com.apple.smbd"; then
        echo -e "${YELLOW}File sharing is currently enabled.${NC}"
        echo -e "${YELLOW}Would you like to disable file sharing? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            launchctl unload -w /System/Library/LaunchDaemons/com.apple.AppleFileServer.plist 2>/dev/null || true
            launchctl unload -w /System/Library/LaunchDaemons/com.apple.smbd.plist 2>/dev/null || true
            print_status $? "Disabled file sharing"
        else
            echo -e "${GREEN}Keeping file sharing enabled${NC}"
        fi
    else
        echo -e "${GREEN}File sharing is already disabled${NC}"
    fi
    
    # Check printer sharing
    if lpstat -p 2>/dev/null | grep -q "printer"; then
        echo -e "${YELLOW}Printer sharing may be enabled.${NC}"
        echo -e "${YELLOW}Would you like to disable printer sharing? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            cupsctl --no-share-printers
            print_status $? "Disabled printer sharing"
        else
            echo -e "${GREEN}Keeping printer sharing enabled${NC}"
        fi
    else
        echo -e "${GREEN}No printers found or printer sharing is already disabled${NC}"
    fi
    
    # Check remote login (SSH)
    if systemsetup -getremotelogin 2>/dev/null | grep -q "On"; then
        echo -e "${YELLOW}Remote login (SSH) is currently enabled.${NC}"
        echo -e "${YELLOW}Would you like to disable remote login? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            systemsetup -setremotelogin off 2>/dev/null || true
            print_status $? "Disabled remote login (SSH)"
        else
            echo -e "${GREEN}Keeping remote login enabled${NC}"
        fi
    else
        echo -e "${GREEN}Remote login is already disabled${NC}"
    fi
    
    # Check Bluetooth
    if system_profiler SPBluetoothDataType 2>/dev/null | grep -q "State: On"; then
        echo -e "${YELLOW}Bluetooth is currently enabled.${NC}"
        echo -e "${YELLOW}Consider disabling Bluetooth if not in use (manual step)${NC}"
    else
        echo -e "${GREEN}Bluetooth is already disabled${NC}"
    fi
}

# Enable VPN if available
check_vpn() {
    echo -e "\n${YELLOW}Checking VPN status...${NC}"
    
    # This is a simple check - you may need to adapt this to your VPN solution
    VPN_INTERFACES=$(ifconfig | grep -E "utun|tun|ppp" | awk '{print $1}' | tr -d ':')
    
    if [ -z "$VPN_INTERFACES" ]; then
        echo -e "${RED}No active VPN detected.${NC}"
        echo -e "${YELLOW}It's recommended to use a VPN on public WiFi networks.${NC}"
    else
        echo -e "${GREEN}VPN appears to be active on interface(s): $VPN_INTERFACES${NC}"
    fi
}

# Check for system updates
check_updates() {
    echo -e "\n${YELLOW}Checking for system updates...${NC}"
    
    # Check for software updates
    softwareupdate -l | cat
    
    echo -e "${YELLOW}It's important to keep your system updated with the latest security patches.${NC}"
}

# Restore settings from backup
restore_settings() {
    echo -e "\n${YELLOW}Available backups:${NC}"
    ls -1 "$BACKUP_DIR" 2>/dev/null | grep -v "README" | grep -v "latest.bak" || echo "No backups found."
    
    echo -e "${YELLOW}Enter backup filename to restore (or 'latest' for most recent, or press Enter to skip):${NC}"
    read -r backup_file
    
    if [ -z "$backup_file" ]; then
        echo -e "${YELLOW}Skipping restore.${NC}"
        return
    fi
    
    if [ "$backup_file" = "latest" ]; then
        FULL_BACKUP_PATH="$BACKUP_DIR/latest.bak"
    else
        FULL_BACKUP_PATH="$BACKUP_DIR/$backup_file"
    fi
    
    if [ ! -f "$FULL_BACKUP_PATH" ]; then
        echo -e "${RED}Backup file not found: $FULL_BACKUP_PATH${NC}"
        return 1
    fi
    
    # Verify backup integrity
    if ! verify_backup "$FULL_BACKUP_PATH"; then
        echo -e "${RED}Backup file appears to be corrupted or incomplete.${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Restoring settings from $FULL_BACKUP_PATH...${NC}"
    
    # Get current network interface
    INTERFACE=$(networksetup -listallhardwareports | grep -A 1 "Wi-Fi" | grep "Device" | awk '{print $2}')
    
    if [ -z "$INTERFACE" ]; then
        echo -e "${RED}Could not determine WiFi interface. Using default 'en0'.${NC}"
        INTERFACE="en0"
    fi
    
    # Restore DNS settings
    DNS_SERVERS=$(grep -A 1 "# DNS Settings Backup" "$FULL_BACKUP_PATH" | tail -1)
    if [ "$DNS_SERVERS" = "There aren't any DNS Servers set on Wi-Fi." ]; then
        networksetup -setdnsservers "$INTERFACE" "Empty"
    else
        networksetup -setdnsservers "$INTERFACE" $DNS_SERVERS
    fi
    print_status $? "Restored DNS settings"
    
    # Restore firewall settings
    FIREWALL_STATE=$(grep "FIREWALL_STATE" "$FULL_BACKUP_PATH" | cut -d= -f2)
    STEALTH_MODE=$(grep "STEALTH_MODE" "$FULL_BACKUP_PATH" | cut -d= -f2)
    BLOCK_ALL=$(grep "BLOCK_ALL" "$FULL_BACKUP_PATH" | cut -d= -f2)
    
    if [ "$FIREWALL_STATE" = "yes" ]; then
        /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
    else
        /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off
    fi
    
    if [ "$STEALTH_MODE" = "yes" ]; then
        /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
    else
        /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode off
    fi
    
    if [ "$BLOCK_ALL" = "yes" ]; then
        /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on
    else
        /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall off
    fi
    print_status $? "Restored firewall settings"
    
    # Restore sharing settings
    SCREEN_SHARING=$(grep "SCREEN_SHARING" "$FULL_BACKUP_PATH" | cut -d= -f2)
    FILE_SHARING_AFP=$(grep "FILE_SHARING_AFP" "$FULL_BACKUP_PATH" | cut -d= -f2)
    FILE_SHARING_SMB=$(grep "FILE_SHARING_SMB" "$FULL_BACKUP_PATH" | cut -d= -f2)
    REMOTE_LOGIN=$(grep "REMOTE_LOGIN" "$FULL_BACKUP_PATH" | cut -d= -f2)
    
    if [ "$SCREEN_SHARING" -gt 0 ]; then
        launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
    fi
    
    if [ "$FILE_SHARING_AFP" -gt 0 ]; then
        launchctl load -w /System/Library/LaunchDaemons/com.apple.AppleFileServer.plist 2>/dev/null || true
    fi
    
    if [ "$FILE_SHARING_SMB" -gt 0 ]; then
        launchctl load -w /System/Library/LaunchDaemons/com.apple.smbd.plist 2>/dev/null || true
    fi
    
    if [ "$REMOTE_LOGIN" = "On" ]; then
        systemsetup -setremotelogin on 2>/dev/null || true
    fi
    print_status $? "Restored sharing settings"
    
    # Flush DNS cache
    dscacheutil -flushcache
    killall -HUP mDNSResponder 2>/dev/null || true
    print_status $? "Flushed DNS cache"
    
    echo -e "${GREEN}Successfully restored settings from backup!${NC}"
}

# Verify backup integrity
verify_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        return 1
    fi
    
    # Check if backup has required sections
    if ! grep -q "# DNS Settings Backup" "$backup_file" || \
       ! grep -q "# Firewall Settings Backup" "$backup_file" || \
       ! grep -q "# Sharing Settings Backup" "$backup_file"; then
        return 1
    fi
    
    return 0
}

# Show menu
show_menu() {
    echo -e "\n${BLUE}=========================================================${NC}"
    echo -e "${BLUE}                      MENU OPTIONS                       ${NC}"
    echo -e "${BLUE}=========================================================${NC}"
    echo -e "1) Apply security measures for public WiFi"
    echo -e "2) Restore settings from backup"
    echo -e "3) Quick restore from latest backup"
    echo -e "4) Exit"
    echo -e "${YELLOW}Enter your choice [1-4]:${NC}"
    read -r choice
    
    case $choice in
        1)
            apply_security_measures
            ;;
        2)
            restore_settings
            ;;
        3)
            quick_restore
            ;;
        4)
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please try again.${NC}"
            show_menu
            ;;
    esac
}

# Quick restore from latest backup
quick_restore() {
    if [ -L "$BACKUP_DIR/latest.bak" ] && [ -f "$BACKUP_DIR/latest.bak" ]; then
        echo -e "${YELLOW}Performing quick restore from latest backup...${NC}"
        
        if verify_backup "$BACKUP_DIR/latest.bak"; then
            FULL_BACKUP_PATH="$BACKUP_DIR/latest.bak"
            
            # Get current network interface
            INTERFACE=$(networksetup -listallhardwareports | grep -A 1 "Wi-Fi" | grep "Device" | awk '{print $2}')
            
            if [ -z "$INTERFACE" ]; then
                echo -e "${RED}Could not determine WiFi interface. Using default 'en0'.${NC}"
                INTERFACE="en0"
            fi
            
            # Restore DNS settings
            DNS_SERVERS=$(grep -A 1 "# DNS Settings Backup" "$FULL_BACKUP_PATH" | tail -1)
            if [ "$DNS_SERVERS" = "There aren't any DNS Servers set on Wi-Fi." ]; then
                networksetup -setdnsservers "$INTERFACE" "Empty"
            else
                networksetup -setdnsservers "$INTERFACE" $DNS_SERVERS
            fi
            print_status $? "Restored DNS settings"
            
            # Restore firewall settings
            FIREWALL_STATE=$(grep "FIREWALL_STATE" "$FULL_BACKUP_PATH" | cut -d= -f2)
            STEALTH_MODE=$(grep "STEALTH_MODE" "$FULL_BACKUP_PATH" | cut -d= -f2)
            BLOCK_ALL=$(grep "BLOCK_ALL" "$FULL_BACKUP_PATH" | cut -d= -f2)
            
            if [ "$FIREWALL_STATE" = "yes" ]; then
                /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
            else
                /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off
            fi
            
            if [ "$STEALTH_MODE" = "yes" ]; then
                /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
            else
                /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode off
            fi
            
            if [ "$BLOCK_ALL" = "yes" ]; then
                /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on
            else
                /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall off
            fi
            print_status $? "Restored firewall settings"
            
            # Restore sharing settings
            SCREEN_SHARING=$(grep "SCREEN_SHARING" "$FULL_BACKUP_PATH" | cut -d= -f2)
            FILE_SHARING_AFP=$(grep "FILE_SHARING_AFP" "$FULL_BACKUP_PATH" | cut -d= -f2)
            FILE_SHARING_SMB=$(grep "FILE_SHARING_SMB" "$FULL_BACKUP_PATH" | cut -d= -f2)
            REMOTE_LOGIN=$(grep "REMOTE_LOGIN" "$FULL_BACKUP_PATH" | cut -d= -f2)
            
            if [ "$SCREEN_SHARING" -gt 0 ]; then
                launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
            fi
            
            if [ "$FILE_SHARING_AFP" -gt 0 ]; then
                launchctl load -w /System/Library/LaunchDaemons/com.apple.AppleFileServer.plist 2>/dev/null || true
            fi
            
            if [ "$FILE_SHARING_SMB" -gt 0 ]; then
                launchctl load -w /System/Library/LaunchDaemons/com.apple.smbd.plist 2>/dev/null || true
            fi
            
            if [ "$REMOTE_LOGIN" = "On" ]; then
                systemsetup -setremotelogin on 2>/dev/null || true
            fi
            print_status $? "Restored sharing settings"
            
            # Flush DNS cache
            dscacheutil -flushcache
            killall -HUP mDNSResponder 2>/dev/null || true
            print_status $? "Flushed DNS cache"
            
            echo -e "${GREEN}Successfully restored settings from latest backup!${NC}"
        else
            echo -e "${RED}Latest backup appears to be corrupted or incomplete.${NC}"
            echo -e "${YELLOW}Please use the manual restore option instead.${NC}"
            restore_settings
        fi
    else
        echo -e "${RED}No latest backup found.${NC}"
        echo -e "${YELLOW}Please use the manual restore option instead.${NC}"
        restore_settings
    fi
}

# Apply security measures
apply_security_measures() {
    echo -e "${YELLOW}Applying security measures for public WiFi...${NC}"
    
    # Create backup of current settings
    create_backup_dir
    
    # Enable firewall
    enable_firewall
    
    # Configure secure DNS
    configure_dns
    
    # Check sharing services
    check_sharing
    
    # Check VPN status
    check_vpn
    
    # Check for updates
    check_updates
    
    echo -e "\n${GREEN}Security measures applied!${NC}"
    echo -e "${YELLOW}For continuous monitoring, run the wifi-monitor.sh script.${NC}"
    echo -e "${YELLOW}To restore original settings, run this script again and select option 2 or 3.${NC}"
    echo -e "${BLUE}=========================================================${NC}"
}

# Handle command line arguments
if [ $# -gt 0 ]; then
    case "$1" in
        "on"|"secure")
            apply_security_measures
            exit 0
            ;;
        "off"|"restore")
            quick_restore
            exit 0
            ;;
        "help"|"-h"|"--help")
            echo -e "Usage: $0 [option]"
            echo -e "Options:"
            echo -e "  on, secure    Apply security measures"
            echo -e "  off, restore  Restore settings from latest backup"
            echo -e "  help, -h      Show this help message"
            echo -e "  (no option)   Show interactive menu"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo -e "Use '$0 help' for usage information."
            exit 1
            ;;
    esac
fi

# Create README in backup directory if it doesn't exist
if [ ! -f "$BACKUP_DIR/README" ]; then
    mkdir -p "$BACKUP_DIR"
    cat > "$BACKUP_DIR/README" << EOF
This directory contains backups of your system settings before applying WiFi security measures.
To restore settings, run the wifi-secure.sh script and select option 2 or 3.

You can also use command line options:
  wifi-secure.sh on     - Apply security measures
  wifi-secure.sh off    - Restore settings from latest backup
EOF
fi

# Disable exit on error for the menu (to allow for user input)
set +e

# Show menu
show_menu 