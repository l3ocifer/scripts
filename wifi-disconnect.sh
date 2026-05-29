#!/bin/bash
#
# wifi-disconnect.sh - A script to safely disconnect from public WiFi
#
# This script resets network settings, clears caches, and restores
# security settings when disconnecting from a public WiFi network.

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

# Print banner
echo -e "${BLUE}=========================================================${NC}"
echo -e "${BLUE}           Safe Public WiFi Disconnection                ${NC}"
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

# Get current WiFi network
get_current_network() {
    CURRENT_WIFI=$(networksetup -getairportnetwork en0 | awk -F': ' '{print $2}')
    echo -e "${YELLOW}Currently connected to: $CURRENT_WIFI${NC}"
}

# Disconnect from WiFi
disconnect_wifi() {
    echo -e "\n${YELLOW}Would you like to disconnect from WiFi? (y/n)${NC}"
    read -r response
    
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo -e "\n${YELLOW}Disconnecting from WiFi network...${NC}"
        
        # Turn off WiFi
        networksetup -setairportpower en0 off
        print_status $? "Turned off WiFi"
        
        sleep 2
        
        # Turn WiFi back on
        networksetup -setairportpower en0 on
        print_status $? "Turned WiFi back on"
    else
        echo -e "${GREEN}Keeping WiFi connection active${NC}"
    fi
}

# Reset DNS settings
reset_dns() {
    echo -e "\n${YELLOW}Would you like to reset DNS settings to DHCP? (y/n)${NC}"
    read -r response
    
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo -e "\n${YELLOW}Resetting DNS settings...${NC}"
        
        # Get current network interface
        INTERFACE=$(networksetup -listallhardwareports | grep -A 1 "Wi-Fi" | grep "Device" | awk '{print $2}')
        
        if [ -z "$INTERFACE" ]; then
            echo -e "${RED}Could not determine WiFi interface. Using default 'en0'.${NC}"
            INTERFACE="en0"
        fi
        
        # Set DNS to automatic (DHCP)
        networksetup -setdnsservers "$INTERFACE" "Empty"
        print_status $? "Reset DNS servers to DHCP"
        
        # Flush DNS cache
        dscacheutil -flushcache
        killall -HUP mDNSResponder 2>/dev/null || true
        print_status $? "Flushed DNS cache"
    else
        echo -e "${GREEN}Keeping current DNS settings${NC}"
    fi
}

# Clear network caches
clear_caches() {
    echo -e "\n${YELLOW}Would you like to clear network caches? (y/n)${NC}"
    read -r response
    
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo -e "\n${YELLOW}Clearing network caches...${NC}"
        
        # Clear ARP cache
        arp -ad
        print_status $? "Cleared ARP cache"
        
        # Clear routing table (except for default routes)
        netstat -rn | grep -v default | grep -v "Destination" | awk '{print $1}' | while read route; do
            route delete "$route" >/dev/null 2>&1 || true
        done
        print_status $? "Cleared routing table"
        
        # Flush DNS cache again
        dscacheutil -flushcache
        killall -HUP mDNSResponder 2>/dev/null || true
        print_status $? "Flushed DNS cache again"
    else
        echo -e "${GREEN}Skipping network cache clearing${NC}"
    fi
}

# Reset firewall to default settings
reset_firewall() {
    echo -e "\n${YELLOW}Would you like to reset firewall settings? (y/n)${NC}"
    read -r response
    
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo -e "\n${YELLOW}Resetting firewall to default settings...${NC}"
        
        # Reset firewall to default settings
        /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
        print_status $? "Enabled firewall"
        
        # Disable stealth mode if desired (comment out if you want to keep stealth mode)
        # /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode off
        # print_status $? "Disabled stealth mode"
        
        # Allow signed applications
        /usr/libexec/ApplicationFirewall/socketfilterfw --setallowsigned on
        print_status $? "Allowing signed applications"
        
        # Disable block all
        /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall off
        print_status $? "Disabled block all incoming connections"
    else
        echo -e "${GREEN}Keeping current firewall settings${NC}"
    fi
}

# Re-enable sharing services if needed
enable_sharing() {
    echo -e "\n${YELLOW}Would you like to re-enable sharing services? (y/n)${NC}"
    read -r response
    
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo -e "\n${YELLOW}Re-enabling sharing services...${NC}"
        
        # Enable screen sharing if needed
        echo -e "${YELLOW}Enable screen sharing? (y/n)${NC}"
        read -r screen_response
        if [[ "$screen_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
            print_status $? "Enabled screen sharing"
        fi
        
        # Enable file sharing if needed
        echo -e "${YELLOW}Enable file sharing? (y/n)${NC}"
        read -r file_response
        if [[ "$file_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            launchctl load -w /System/Library/LaunchDaemons/com.apple.AppleFileServer.plist 2>/dev/null || true
            launchctl load -w /System/Library/LaunchDaemons/com.apple.smbd.plist 2>/dev/null || true
            print_status $? "Enabled file sharing"
        fi
        
        # Enable printer sharing if needed
        echo -e "${YELLOW}Enable printer sharing? (y/n)${NC}"
        read -r printer_response
        if [[ "$printer_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            cupsctl --share-printers
            print_status $? "Enabled printer sharing"
        fi
        
        # Enable remote login (SSH) if needed
        echo -e "${YELLOW}Enable remote login (SSH)? (y/n)${NC}"
        read -r ssh_response
        if [[ "$ssh_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            systemsetup -setremotelogin on 2>/dev/null || true
            print_status $? "Enabled remote login (SSH)"
        fi
    else
        echo -e "${GREEN}Keeping sharing services as is${NC}"
    fi
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

# Restore from backup
restore_from_backup() {
    echo -e "\n${YELLOW}Would you like to restore settings from a backup? (y/n)${NC}"
    read -r response
    
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
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
    else
        echo -e "${GREEN}Skipping backup restore${NC}"
    fi
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
            restore_from_backup
        fi
    else
        echo -e "${RED}No latest backup found.${NC}"
        echo -e "${YELLOW}Please use the manual restore option instead.${NC}"
        restore_from_backup
    fi
}

# Show menu
show_menu() {
    echo -e "\n${BLUE}=========================================================${NC}"
    echo -e "${BLUE}                      MENU OPTIONS                       ${NC}"
    echo -e "${BLUE}=========================================================${NC}"
    echo -e "1) Perform full disconnect and reset (with prompts)"
    echo -e "2) Restore settings from backup"
    echo -e "3) Quick restore from latest backup"
    echo -e "4) Exit"
    echo -e "${YELLOW}Enter your choice [1-4]:${NC}"
    read -r choice
    
    case $choice in
        1)
            perform_disconnect
            ;;
        2)
            restore_from_backup
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

# Perform disconnect
perform_disconnect() {
    echo -e "${YELLOW}Starting safe disconnection from public WiFi...${NC}"
    
    # Get current network
    get_current_network
    
    # Disconnect from WiFi
    disconnect_wifi
    
    # Reset DNS settings
    reset_dns
    
    # Clear network caches
    clear_caches
    
    # Reset firewall
    reset_firewall
    
    # Re-enable sharing services if needed
    enable_sharing
    
    echo -e "\n${GREEN}Successfully processed disconnection from public WiFi!${NC}"
    echo -e "${BLUE}=========================================================${NC}"
}

# Handle command line arguments
if [ $# -gt 0 ]; then
    case "$1" in
        "disconnect")
            perform_disconnect
            exit 0
            ;;
        "restore")
            quick_restore
            exit 0
            ;;
        "help"|"-h"|"--help")
            echo -e "Usage: $0 [option]"
            echo -e "Options:"
            echo -e "  disconnect    Perform disconnect and reset"
            echo -e "  restore       Restore settings from latest backup"
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

# Disable exit on error for the menu (to allow for user input)
set +e

# Show menu
show_menu 