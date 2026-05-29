#!/bin/bash
#
# wifi-monitor.sh - A script to monitor network connections for security on public WiFi
# 
# This script monitors incoming connections, logs suspicious activity,
# and provides alerts to help maintain security on public WiFi networks.

# Exit on error
set -e

# Set colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Log file location
LOG_DIR="$HOME/.logs"
LOG_FILE="$LOG_DIR/wifi-monitor-$(date +%Y-%m-%d).log"
HISTORY_FILE="$LOG_DIR/wifi-connection-history.log"

# Monitoring intervals (in seconds)
CONNECTION_CHECK_INTERVAL=10
ARP_CHECK_INTERVAL=30
PORT_CHECK_INTERVAL=300
TRAFFIC_CHECK_INTERVAL=60

# Known networks (customize this list with your trusted networks)
KNOWN_NETWORKS=("Home" "Work" "Office")

# Common high ports that are usually legitimate
COMMON_HIGH_PORTS=(3000 3001 5000 5001 8000 8080 8443 8888 9000 9001 9090 9443)

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Print usage information
print_usage() {
    echo -e "${BLUE}Usage: $0 [OPTIONS]${NC}"
    echo -e "Monitor network connections for security on public WiFi"
    echo -e ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  -n, --normal       Start monitoring in normal mode"
    echo -e "  -l, --low          Start monitoring in low resource usage mode"
    echo -e "  -q, --quick        Run a quick scan (default if no options provided)"
    echo -e "  -c, --connections  View connection history"
    echo -e "  -f, --file         View current log file"
    echo -e "  -h, --help         Display this help message"
    echo -e ""
    echo -e "${YELLOW}Numeric Options (for backward compatibility):${NC}"
    echo -e "  1                  Start monitoring in normal mode"
    echo -e "  2                  Start monitoring in low resource usage mode"
    echo -e "  3                  Run a quick scan"
    echo -e "  4                  View connection history"
    echo -e "  5                  View current log file"
    echo -e ""
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  sudo $0                 Run a quick scan (default)"
    echo -e "  sudo $0 -n              Start monitoring in normal mode"
    echo -e "  sudo $0 --low           Start monitoring in low resource usage mode"
    echo -e "  sudo $0 -q | grep ALERT Check for security alerts only"
    echo -e "  sudo $0 -c              View connection history"
    echo -e "  sudo $0 3               Run a quick scan (numeric option)"
    echo -e ""
    echo -e "${YELLOW}Note:${NC} This script requires sudo privileges to access network information."
}

# Print banner
print_banner() {
    echo -e "${BLUE}=========================================================${NC}"
    echo -e "${BLUE}           WiFi Network Security Monitor                 ${NC}"
    echo -e "${BLUE}=========================================================${NC}"
    echo -e "${YELLOW}Monitoring network activity. Press Ctrl+C to stop.${NC}\n"
}

# Check if script is run with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this script with sudo privileges${NC}"
    exit 1
fi

# Log function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Log to file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Display to console with color based on level
    case "$level" in
        "INFO")
            echo -e "${GREEN}[$timestamp] [$level] $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}[$timestamp] [$level] $message${NC}"
            ;;
        "ALERT")
            echo -e "${RED}[$timestamp] [$level] $message${NC}"
            # Optional: Add system notification for alerts
            if command -v osascript &> /dev/null; then
                osascript -e "display notification \"$message\" with title \"WiFi Security Alert\""
            fi
            ;;
    esac
}

# Get current network information
get_network_info() {
    # Get current network interface
    INTERFACE=$(networksetup -listallhardwareports | grep -A 1 "Wi-Fi" | grep "Device" | awk '{print $2}')
    
    if [ -z "$INTERFACE" ]; then
        log_message "WARNING" "Could not determine WiFi interface. Using default 'en0'."
        INTERFACE="en0"
    fi
    
    # Try multiple methods to get WiFi network name
    CURRENT_WIFI=""
    
    # Method 1: Using networksetup
    CURRENT_WIFI=$(networksetup -getairportnetwork $INTERFACE 2>/dev/null | awk -F': ' '{print $2}')
    
    # Method 2: Using airport command if Method 1 failed
    if [ -z "$CURRENT_WIFI" ] && [ -f "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport" ]; then
        CURRENT_WIFI=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | awk '/ SSID/ {print $2}')
    fi
    
    # Method 3: Using defaults command if Methods 1 and 2 failed
    if [ -z "$CURRENT_WIFI" ]; then
        CURRENT_WIFI=$(defaults read /Library/Preferences/SystemConfiguration/com.apple.airport.preferences 2>/dev/null | grep -A 1 "LastConnected" | grep "SSIDString" | cut -d '"' -f 2)
    fi
    
    # Method 4: Using system_profiler if all other methods failed
    if [ -z "$CURRENT_WIFI" ]; then
        CURRENT_WIFI=$(system_profiler SPNetworkDataType 2>/dev/null | grep -A 5 "Wi-Fi" | grep "SSID" | awk '{print $2}')
    fi
    
    # Method 5: Using scutil (more reliable on newer macOS versions)
    if [ -z "$CURRENT_WIFI" ]; then
        CURRENT_WIFI=$(scutil --get LocalHostName 2>/dev/null)
        if [ -n "$CURRENT_WIFI" ]; then
            CURRENT_WIFI="$CURRENT_WIFI Network"
        fi
    fi
    
    if [ -z "$CURRENT_WIFI" ]; then
        log_message "WARNING" "Could not determine WiFi network name."
        CURRENT_WIFI="Unknown"
    fi
    
    CURRENT_IP=$(ipconfig getifaddr $INTERFACE)
    
    if [ -z "$CURRENT_IP" ]; then
        log_message "WARNING" "Could not determine IP address. WiFi may not be connected."
        CURRENT_IP="Unknown"
    fi
    
    log_message "INFO" "Connected to WiFi network: $CURRENT_WIFI"
    log_message "INFO" "Your IP address: $CURRENT_IP"
    
    # Get public IP address
    get_public_ip
    
    # Get MAC address
    MAC_ADDRESS=$(ifconfig $INTERFACE | awk '/ether/{print $2}')
    log_message "INFO" "Your MAC address: $MAC_ADDRESS"
    
    # Get subnet mask
    SUBNET_MASK=$(ifconfig $INTERFACE | awk '/netmask/{print $4}')
    log_message "INFO" "Subnet mask: $SUBNET_MASK"
    
    # Get default gateway
    DEFAULT_GATEWAY=$(netstat -rn | grep default | grep $INTERFACE | awk '{print $2}')
    
    if [ -z "$DEFAULT_GATEWAY" ]; then
        log_message "WARNING" "Could not determine default gateway."
        DEFAULT_GATEWAY="Unknown"
    else
        log_message "INFO" "Default gateway: $DEFAULT_GATEWAY"
        
        # Get gateway MAC address
        GATEWAY_MAC=$(arp -a | grep "$DEFAULT_GATEWAY" | awk '{print $4}')
        if [ -n "$GATEWAY_MAC" ]; then
            log_message "INFO" "Gateway MAC address: $GATEWAY_MAC"
        fi
    fi
    
    # Get DNS servers - fixed method
    log_message "INFO" "DNS servers:"
    DNS_SERVERS=$(scutil --dns | grep 'nameserver\[[0-9]*\]' | sort | uniq | awk '{print $3}')
    if [ -z "$DNS_SERVERS" ]; then
        log_message "INFO" "Using DHCP-provided DNS servers"
    else
        echo "$DNS_SERVERS" | while read -r dns; do
            log_message "INFO" "- $dns"
        done
    fi
    
    # Check if this is a known network
    KNOWN_NETWORK=false
    for network in "${KNOWN_NETWORKS[@]}"; do
        if [[ "$CURRENT_WIFI" == "$network" ]]; then
            log_message "INFO" "Connected to a known network. Lower security monitoring will be used."
            KNOWN_NETWORK=true
            break
        fi
    done
    
    if [ "$KNOWN_NETWORK" = false ]; then
        log_message "WARNING" "Connected to an unknown network. Higher security monitoring will be used."
    fi
    
    # Display network signal strength
    if command -v /System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport &> /dev/null; then
        SIGNAL_INFO=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I)
        SIGNAL_STRENGTH=$(echo "$SIGNAL_INFO" | awk '/ agrCtlRSSI/ {print $2}')
        NOISE=$(echo "$SIGNAL_INFO" | awk '/ agrCtlNoise/ {print $2}')
        CHANNEL=$(echo "$SIGNAL_INFO" | awk '/ channel/ {print $2}')
        
        if [ -n "$SIGNAL_STRENGTH" ] && [ -n "$NOISE" ]; then
            SNR=$((SIGNAL_STRENGTH - NOISE))
            log_message "INFO" "WiFi signal: ${SIGNAL_STRENGTH} dBm, Noise: ${NOISE} dBm, SNR: ${SNR} dB, Channel: ${CHANNEL}"
            
            # Interpret signal quality
            if [ "$SNR" -gt 40 ]; then
                log_message "INFO" "Signal quality: Excellent"
            elif [ "$SNR" -gt 25 ]; then
                log_message "INFO" "Signal quality: Good"
            elif [ "$SNR" -gt 15 ]; then
                log_message "INFO" "Signal quality: Fair"
            else
                log_message "WARNING" "Signal quality: Poor - connection may be unstable"
            fi
        fi
    fi
}

# Get public IP address
get_public_ip() {
    log_message "INFO" "Checking public IP address..."
    
    # Try multiple services in case one is down
    PUBLIC_IP=""
    
    # Method 1: Using DNS query (most reliable and doesn't require HTTP)
    if command -v dig &> /dev/null; then
        PUBLIC_IP=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)
    fi
    
    # Method 2: Using curl if dig failed
    if [ -z "$PUBLIC_IP" ] && command -v curl &> /dev/null; then
        PUBLIC_IP=$(curl -s https://ipinfo.io/ip 2>/dev/null)
    fi
    
    # Method 3: Using wget if curl failed
    if [ -z "$PUBLIC_IP" ] && command -v wget &> /dev/null; then
        PUBLIC_IP=$(wget -qO- https://ipinfo.io/ip 2>/dev/null)
    fi
    
    if [ -n "$PUBLIC_IP" ]; then
        log_message "INFO" "Public IP address: $PUBLIC_IP"
        
        # Check if public IP is in a known range
        if [[ "$PUBLIC_IP" == 10.* ]] || [[ "$PUBLIC_IP" == 172.1[6-9].* ]] || [[ "$PUBLIC_IP" == 172.2[0-9].* ]] || [[ "$PUBLIC_IP" == 172.3[0-1].* ]] || [[ "$PUBLIC_IP" == 192.168.* ]]; then
            log_message "WARNING" "Your public IP appears to be a private IP address. You may be behind Carrier-Grade NAT (CGN) or a proxy."
        fi
    else
        log_message "WARNING" "Could not determine public IP address."
    fi
}

# Monitor open ports with enhanced details
check_open_ports() {
    log_message "INFO" "Checking for open ports..."
    OPEN_PORTS=$(sudo lsof -i -P -n | grep LISTEN)
    
    # Only log the full list to the file, not to the console
    echo "--- Open Ports at $(date) ---" >> "$LOG_FILE"
    echo "$OPEN_PORTS" >> "$LOG_FILE"
    echo "--- End of Open Ports List ---" >> "$LOG_FILE"
    
    # Count open ports
    PORT_COUNT=$(echo "$OPEN_PORTS" | wc -l | tr -d ' ')
    log_message "INFO" "Found $PORT_COUNT listening ports"
    
    # Create a deduplicated list of important ports with their processes
    IMPORTANT_PORTS=$(echo "$OPEN_PORTS" | grep -E ':(22|80|443|3389|5900|5901|8080|8443)' | awk '{print $9":"$1}' | sort -u)
    
    # Display the most important open ports on screen
    if [ -n "$IMPORTANT_PORTS" ]; then
        log_message "INFO" "Important open ports:"
        echo "$IMPORTANT_PORTS" | head -5 | while read -r port_info; do
            PORT=$(echo "$port_info" | cut -d: -f2)
            PROCESS=$(echo "$port_info" | cut -d: -f3)
            
            # Get more details about the process - improved to handle missing data
            PROCESS_LINE=$(echo "$OPEN_PORTS" | grep -E ":$PORT.*$PROCESS" | head -1)
            PID=$(echo "$PROCESS_LINE" | awk '{print $2}')
            USER=$(echo "$PROCESS_LINE" | awk '{print $3}')
            
            # Ensure PID and USER have values
            PID=${PID:-"N/A"}
            USER=${USER:-"N/A"}
            
            # Get process path
            PROCESS_PATH=$(ps -o command= -p "$PID" 2>/dev/null | head -1)
            
            # Add service name if known
            SERVICE_NAME=""
            case $PORT in
                22) SERVICE_NAME=" (SSH)" ;;
                80) SERVICE_NAME=" (HTTP)" ;;
                443) SERVICE_NAME=" (HTTPS)" ;;
                3389) SERVICE_NAME=" (RDP)" ;;
                5900) SERVICE_NAME=" (VNC/Screen Sharing)" ;;
                5901) SERVICE_NAME=" (VNC/Screen Sharing)" ;;
                8080) SERVICE_NAME=" (HTTP Alternate)" ;;
                8443) SERVICE_NAME=" (HTTPS Alternate)" ;;
            esac
            
            log_message "INFO" "Port $PORT$SERVICE_NAME is open by $PROCESS (PID: $PID, User: $USER)"
            if [ -n "$PROCESS_PATH" ]; then
                log_message "INFO" "  → Process: $PROCESS_PATH"
            fi
        done
    else
        log_message "INFO" "No common service ports are open"
    fi
    
    # Check for commonly exploited ports
    SUSPICIOUS_PORTS="21 23 25 53 445 1433 3306 5432"
    FOUND_SUSPICIOUS=false
    for port in $SUSPICIOUS_PORTS; do
        if echo "$OPEN_PORTS" | grep -q ":$port "; then
            FOUND_SUSPICIOUS=true
            PROCESS=$(echo "$OPEN_PORTS" | grep ":$port " | awk '{print $1}')
            PID=$(echo "$OPEN_PORTS" | grep ":$port " | awk '{print $2}')
            USER=$(echo "$OPEN_PORTS" | grep ":$port " | awk '{print $3}')
            
            # Ensure PID and USER have values
            PID=${PID:-"N/A"}
            USER=${USER:-"N/A"}
            
            # Get more details about the process
            PROCESS_PATH=$(ps -o command= -p "$PID" 2>/dev/null | head -1)
            
            # Add service name
            SERVICE_NAME=""
            case $port in
                21) SERVICE_NAME=" (FTP)" ;;
                23) SERVICE_NAME=" (Telnet)" ;;
                25) SERVICE_NAME=" (SMTP)" ;;
                53) SERVICE_NAME=" (DNS)" ;;
                445) SERVICE_NAME=" (SMB)" ;;
                1433) SERVICE_NAME=" (MSSQL)" ;;
                3306) SERVICE_NAME=" (MySQL)" ;;
                5432) SERVICE_NAME=" (PostgreSQL)" ;;
            esac
            
            log_message "WARNING" "Potentially sensitive port $port$SERVICE_NAME is open by $PROCESS (PID: $PID, User: $USER)"
            if [ -n "$PROCESS_PATH" ]; then
                log_message "WARNING" "  → Process: $PROCESS_PATH"
            fi
        fi
    done
    
    if [ "$FOUND_SUSPICIOUS" = false ]; then
        log_message "INFO" "No potentially sensitive ports detected"
    fi
    
    # Check for unusual high ports (above 10000) that might be suspicious
    UNUSUAL_HIGH_PORTS=$(echo "$OPEN_PORTS" | grep -E ':[1-9][0-9]{4,}' | grep -v -E ':(10000|20000|30000|40000|50000)')
    if [ -n "$UNUSUAL_HIGH_PORTS" ]; then
        log_message "INFO" "Unusual high ports detected:"
        echo "$UNUSUAL_HIGH_PORTS" | awk '{print $9":"$1}' | sort -u | head -3 | while read -r port_info; do
            PORT=$(echo "$port_info" | cut -d: -f2)
            PROCESS=$(echo "$port_info" | cut -d: -f3)
            
            # Get more details
            PROCESS_LINE=$(echo "$UNUSUAL_HIGH_PORTS" | grep -E ":$PORT.*$PROCESS" | head -1)
            PID=$(echo "$PROCESS_LINE" | awk '{print $2}')
            
            # Ensure PID has a value
            PID=${PID:-"N/A"}
            
            log_message "INFO" "Port $PORT is open by $PROCESS (PID: $PID)"
        done
    fi
}

# Monitor network traffic volume
monitor_traffic_volume() {
    log_message "INFO" "Monitoring network traffic volume..."
    
    # Get initial network stats - improved to handle different macOS versions
    INITIAL_IN=$(netstat -ib | grep -A 1 $INTERFACE | tail -1 | awk '{print $7}')
    INITIAL_OUT=$(netstat -ib | grep -A 1 $INTERFACE | tail -1 | awk '{print $10}')
    
    # If the above doesn't work, try alternative column positions
    if [[ -z "$INITIAL_IN" || "$INITIAL_IN" == "0" ]]; then
        INITIAL_IN=$(netstat -ib | grep -A 1 $INTERFACE | tail -1 | awk '{print $5}')
        INITIAL_OUT=$(netstat -ib | grep -A 1 $INTERFACE | tail -1 | awk '{print $8}')
    fi
    
    # If still not working, try another approach with ifconfig
    if [[ -z "$INITIAL_IN" || "$INITIAL_IN" == "0" ]]; then
        INITIAL_IN=$(ifconfig $INTERFACE | grep "bytes" | awk '{print $2}' | cut -d: -f2)
        INITIAL_OUT=$(ifconfig $INTERFACE | grep "bytes" | awk '{print $6}' | cut -d: -f2)
    fi
    
    # If still not working, try nettop as a last resort
    if [[ -z "$INITIAL_IN" || "$INITIAL_IN" == "0" ]]; then
        if command -v nettop &> /dev/null; then
            NETTOP_DATA=$(nettop -P -L 1 -n -J bytes_in,bytes_out | grep -v "nettop")
            INITIAL_IN=$(echo "$NETTOP_DATA" | awk '{sum += $4} END {print sum}')
            INITIAL_OUT=$(echo "$NETTOP_DATA" | awk '{sum += $5} END {print sum}')
        fi
    fi
    
    # Ensure we have numeric values, default to 0 if not
    if ! [[ "$INITIAL_IN" =~ ^[0-9]+$ ]]; then
        log_message "WARNING" "Could not get initial incoming traffic value, defaulting to 0"
        INITIAL_IN=0
    fi
    
    if ! [[ "$INITIAL_OUT" =~ ^[0-9]+$ ]]; then
        log_message "WARNING" "Could not get initial outgoing traffic value, defaulting to 0"
        INITIAL_OUT=0
    fi
    
    # Log the initial values for debugging
    echo "Initial traffic values - IN: $INITIAL_IN, OUT: $INITIAL_OUT" >> "$LOG_FILE"
    
    INITIAL_TIME=$(date +%s)
    
    while true; do
        sleep $TRAFFIC_CHECK_INTERVAL
        
        # Get current network stats - with the same fallbacks as above
        CURRENT_IN=$(netstat -ib | grep -A 1 $INTERFACE | tail -1 | awk '{print $7}')
        CURRENT_OUT=$(netstat -ib | grep -A 1 $INTERFACE | tail -1 | awk '{print $10}')
        
        # Try alternative column positions if needed
        if [[ -z "$CURRENT_IN" || "$CURRENT_IN" == "0" ]]; then
            CURRENT_IN=$(netstat -ib | grep -A 1 $INTERFACE | tail -1 | awk '{print $5}')
            CURRENT_OUT=$(netstat -ib | grep -A 1 $INTERFACE | tail -1 | awk '{print $8}')
        fi
        
        # Try ifconfig if netstat doesn't work
        if [[ -z "$CURRENT_IN" || "$CURRENT_IN" == "0" ]]; then
            CURRENT_IN=$(ifconfig $INTERFACE | grep "bytes" | awk '{print $2}' | cut -d: -f2)
            CURRENT_OUT=$(ifconfig $INTERFACE | grep "bytes" | awk '{print $6}' | cut -d: -f2)
        fi
        
        # Try nettop as a last resort
        if [[ -z "$CURRENT_IN" || "$CURRENT_IN" == "0" ]]; then
            if command -v nettop &> /dev/null; then
                NETTOP_DATA=$(nettop -P -L 1 -n -J bytes_in,bytes_out | grep -v "nettop")
                CURRENT_IN=$(echo "$NETTOP_DATA" | awk '{sum += $4} END {print sum}')
                CURRENT_OUT=$(echo "$NETTOP_DATA" | awk '{sum += $5} END {print sum}')
            fi
        fi
        
        # Ensure we have numeric values, default to previous values if not
        if ! [[ "$CURRENT_IN" =~ ^[0-9]+$ ]]; then
            log_message "WARNING" "Could not get current incoming traffic value, using previous value"
            CURRENT_IN=$INITIAL_IN
        fi
        
        if ! [[ "$CURRENT_OUT" =~ ^[0-9]+$ ]]; then
            log_message "WARNING" "Could not get current outgoing traffic value, using previous value"
            CURRENT_OUT=$INITIAL_OUT
        fi
        
        # Log the current values for debugging
        echo "Current traffic values - IN: $CURRENT_IN, OUT: $CURRENT_OUT" >> "$LOG_FILE"
        
        CURRENT_TIME=$(date +%s)
        
        # Calculate traffic rate
        TIME_DIFF=$((CURRENT_TIME - INITIAL_TIME))
        if [ $TIME_DIFF -gt 0 ]; then
            # Make sure we have numeric values
            if [[ "$CURRENT_IN" =~ ^[0-9]+$ ]] && [[ "$INITIAL_IN" =~ ^[0-9]+$ ]] && \
               [[ "$CURRENT_OUT" =~ ^[0-9]+$ ]] && [[ "$INITIAL_OUT" =~ ^[0-9]+$ ]]; then
                
                IN_DIFF=$((CURRENT_IN - INITIAL_IN))
                OUT_DIFF=$((CURRENT_OUT - INITIAL_OUT))
                
                # Ensure we don't have negative values (can happen on counter reset)
                if [ $IN_DIFF -lt 0 ]; then IN_DIFF=$CURRENT_IN; fi
                if [ $OUT_DIFF -lt 0 ]; then OUT_DIFF=$CURRENT_OUT; fi
                
                # Calculate KB/s
                IN_RATE=$(echo "scale=2; $IN_DIFF / $TIME_DIFF / 1024" | bc)
                OUT_RATE=$(echo "scale=2; $OUT_DIFF / $TIME_DIFF / 1024" | bc)
                
                # Format with colors based on traffic volume
                if (( $(echo "$IN_RATE > 500" | bc -l) )); then
                    log_message "WARNING" "Traffic: ↓ ${IN_RATE} KB/s, ↑ ${OUT_RATE} KB/s"
                else
                    log_message "INFO" "Traffic: ↓ ${IN_RATE} KB/s, ↑ ${OUT_RATE} KB/s"
                fi
                
                # Check for unusually high traffic
                if (( $(echo "$IN_RATE > 1000" | bc -l) )) || (( $(echo "$OUT_RATE > 500" | bc -l) )); then
                    log_message "WARNING" "Unusually high network traffic detected"
                    
                    # Try to identify processes using the most bandwidth
                    log_message "INFO" "Top bandwidth-consuming processes:"
                    if command -v nettop &> /dev/null; then
                        nettop -P -L 1 -n -J bytes_in,bytes_out | head -10 | grep -v "nettop" >> "$LOG_FILE"
                        # Just log to file as nettop output is complex
                        
                        # Also try to get a simplified version for display
                        TOP_PROCESSES=$(nettop -P -L 1 -n | grep -v "nettop" | sort -nrk 10 | head -3)
                        if [ -n "$TOP_PROCESSES" ]; then
                            echo "$TOP_PROCESSES" | while read -r proc_line; do
                                PROC_NAME=$(echo "$proc_line" | awk '{print $1}')
                                log_message "INFO" "  → High bandwidth process: $PROC_NAME"
                            done
                        fi
                    elif command -v lsof &> /dev/null; then
                        # Alternative if nettop is not available
                        log_message "INFO" "Network processes (bandwidth info not available):"
                        lsof -i -P -n | grep -v LISTEN | awk '{print $1}' | sort | uniq -c | sort -nr | head -3 | while read -r line; do
                            COUNT=$(echo "$line" | awk '{print $1}')
                            PROCESS=$(echo "$line" | awk '{print $2}')
                            log_message "INFO" "  → $PROCESS: $COUNT connections"
                        done
                    fi
                fi
            else
                log_message "WARNING" "Could not calculate traffic rate - non-numeric values detected"
                log_message "INFO" "Debug: IN=$CURRENT_IN, OUT=$CURRENT_OUT"
                
                # Try to get direct traffic rate using nettop if available
                if command -v nettop &> /dev/null; then
                    log_message "INFO" "Attempting to get traffic rate directly from nettop..."
                    NETTOP_DATA=$(nettop -P -L 1 -n -J delta_bytes_in,delta_bytes_out | grep -v "nettop")
                    DELTA_IN=$(echo "$NETTOP_DATA" | awk '{sum += $4} END {print sum}')
                    DELTA_OUT=$(echo "$NETTOP_DATA" | awk '{sum += $5} END {print sum}')
                    
                    if [[ "$DELTA_IN" =~ ^[0-9]+$ ]] && [[ "$DELTA_OUT" =~ ^[0-9]+$ ]]; then
                        IN_RATE=$(echo "scale=2; $DELTA_IN / 1024" | bc)
                        OUT_RATE=$(echo "scale=2; $DELTA_OUT / 1024" | bc)
                        log_message "INFO" "Traffic (direct): ↓ ${IN_RATE} KB/s, ↑ ${OUT_RATE} KB/s"
                    fi
                fi
            fi
            
            # Reset counters for next interval
            INITIAL_IN=$CURRENT_IN
            INITIAL_OUT=$CURRENT_OUT
            INITIAL_TIME=$CURRENT_TIME
        fi
    done
}

# Track connection history
track_connection_history() {
    log_message "INFO" "Starting connection history tracking..."
    
    # Initialize connection history file if it doesn't exist
    if [ ! -f "$HISTORY_FILE" ]; then
        echo "# WiFi Connection History" > "$HISTORY_FILE"
        echo "# Format: timestamp,network,local_ip,public_ip,gateway,dns_servers" >> "$HISTORY_FILE"
    fi
    
    # Add current connection to history
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    DNS_SERVERS_COMPACT=$(echo "$DNS_SERVERS" | tr '\n' '|')
    echo "$TIMESTAMP,$CURRENT_WIFI,$CURRENT_IP,$PUBLIC_IP,$DEFAULT_GATEWAY,$DNS_SERVERS_COMPACT" >> "$HISTORY_FILE"
    
    log_message "INFO" "Connection added to history"
    
    # Show recent connection history
    log_message "INFO" "Recent connection history (last 5 connections):"
    tail -5 "$HISTORY_FILE" | grep -v "#" | while IFS=, read -r ts net lip pip gw dns; do
        log_message "INFO" "[$ts] Network: $net, IP: $lip, Public IP: $pip"
    done
}

# Investigate unusual connections with improved filtering
investigate_unusual_connections() {
    log_message "INFO" "Investigating unusual connections..."
    
    # Get all established connections
    ESTABLISHED=$(netstat -an | grep ESTABLISHED)
    
    # Look for connections to unusual ports, excluding common high ports
    EXCLUDE_PATTERN=$(printf "|%s" "${COMMON_HIGH_PORTS[@]}")
    EXCLUDE_PATTERN=${EXCLUDE_PATTERN:1}  # Remove leading |
    
    UNUSUAL_PORTS=$(echo "$ESTABLISHED" | grep -E '\.[1-9][0-9]{4,}' | grep -v -E "\.(${EXCLUDE_PATTERN})")
    if [ -n "$UNUSUAL_PORTS" ]; then
        log_message "WARNING" "Connections to unusual ports detected:"
        echo "$UNUSUAL_PORTS" | head -5 | while read -r line; do
            REMOTE=$(echo "$line" | awk '{print $5}')
            LOCAL=$(echo "$line" | awk '{print $4}')
            
            # Extract remote IP and port
            REMOTE_IP=$(echo "$REMOTE" | cut -d. -f1-4)
            REMOTE_PORT=$(echo "$REMOTE" | cut -d. -f5)
            
            log_message "WARNING" "Connection from $LOCAL to $REMOTE_IP port $REMOTE_PORT"
            
            # Try to find the process using this connection
            PROCESS=$(lsof -i | grep "$REMOTE" | head -1)
            if [ -n "$PROCESS" ]; then
                PROCESS_NAME=$(echo "$PROCESS" | awk '{print $1}')
                PROCESS_PID=$(echo "$PROCESS" | awk '{print $2}')
                log_message "WARNING" "  → Process: $PROCESS_NAME (PID: $PROCESS_PID)"
                
                # Get more details about the process
                PROCESS_CMD=$(ps -p "$PROCESS_PID" -o command= 2>/dev/null | head -1)
                if [ -n "$PROCESS_CMD" ]; then
                    # Truncate command if too long
                    if [ ${#PROCESS_CMD} -gt 80 ]; then
                        PROCESS_CMD="${PROCESS_CMD:0:77}..."
                    fi
                    log_message "INFO" "  → Command: $PROCESS_CMD"
                fi
                
                # Get CPU usage for this process if top is available
                if command -v ps &> /dev/null; then
                    # First try to get PID directly using pgrep with exact match
                    PID=$(pgrep -x "$PROCESS" 2>/dev/null | head -1)
                    
                    # If that fails, try a more flexible approach with case-insensitive partial match
                    if [ -z "$PID" ]; then
                        PID=$(pgrep -i "$PROCESS" 2>/dev/null | head -1)
                    fi
                    
                    # If we found a PID, get its CPU usage
                    if [ -n "$PID" ]; then
                        CPU_USAGE=$(ps -p "$PID" -o %cpu= 2>/dev/null | awk '{print $1}')
                        if [ -n "$CPU_USAGE" ]; then
                            log_message "INFO" "  → CPU usage: ${CPU_USAGE}%"
                        else
                            log_message "INFO" "  → CPU usage: Not available"
                        fi
                    else
                        # If we couldn't get a PID, try using top as a fallback
                        if command -v top &> /dev/null; then
                            CPU_USAGE=$(top -l 1 -stats pid,command,cpu -o cpu | grep -i "$PROCESS" | head -1 | awk '{print $3}')
                            if [ -n "$CPU_USAGE" ]; then
                                # Extract only numeric part if it contains non-numeric characters
                                CPU_USAGE=$(echo "$CPU_USAGE" | grep -o '[0-9.]*')
                                if [ -n "$CPU_USAGE" ]; then
                                    log_message "INFO" "  → CPU usage: ${CPU_USAGE}%"
                                else
                                    log_message "INFO" "  → CPU usage: Not available"
                                fi
                            else
                                log_message "INFO" "  → CPU usage: Not available"
                            fi
                        else
                            log_message "INFO" "  → CPU usage: Not available"
                        fi
                    fi
                else
                    log_message "INFO" "  → CPU usage: Not available (ps command not found)"
                fi
            fi
            
            # Try to get more information about the remote IP
            if command -v whois &> /dev/null; then
                WHOIS_INFO=$(whois "$REMOTE_IP" 2>/dev/null | grep -E "Organization|OrgName|netname|descr" | head -2)
                if [ -n "$WHOIS_INFO" ]; then
                    log_message "INFO" "  → Remote IP info: $(echo "$WHOIS_INFO" | tr '\n' ' ')"
                fi
                
                # Check if this is a known service port
                if command -v grep &> /dev/null && [ -f "/etc/services" ]; then
                    SERVICE=$(grep -w "$REMOTE_PORT" /etc/services | head -1 | awk '{print $1}')
                    if [ -n "$SERVICE" ]; then
                        log_message "INFO" "  → Port $REMOTE_PORT is used by service: $SERVICE"
                    fi
                fi
            fi
        done
    fi
    
    # Look for connections to known suspicious IP ranges
    # This is a very basic check - in a real security tool, you'd use a threat intelligence feed
    SUSPICIOUS_RANGES=("185.147." "185.159." "194.5." "194.87.")
    for range in "${SUSPICIOUS_RANGES[@]}"; do
        SUSPICIOUS=$(echo "$ESTABLISHED" | grep "$range")
        if [ -n "$SUSPICIOUS" ]; then
            log_message "ALERT" "Connection to potentially suspicious IP range detected: $range"
            echo "$SUSPICIOUS" | head -3 | while read -r line; do
                REMOTE=$(echo "$line" | awk '{print $5}')
                LOCAL=$(echo "$line" | awk '{print $4}')
                log_message "ALERT" "Connection from $LOCAL to $REMOTE"
                
                # Try to find the process using this connection
                PROCESS=$(lsof -i | grep "$REMOTE" | head -1)
                if [ -n "$PROCESS" ]; then
                    PROCESS_NAME=$(echo "$PROCESS" | awk '{print $1}')
                    PROCESS_PID=$(echo "$PROCESS" | awk '{print $2}')
                    log_message "ALERT" "  → Process: $PROCESS_NAME (PID: $PROCESS_PID)"
                    
                    # Get more details about the process
                    PROCESS_CMD=$(ps -p "$PROCESS_PID" -o command= 2>/dev/null | head -1)
                    if [ -n "$PROCESS_CMD" ]; then
                        # Truncate command if too long
                        if [ ${#PROCESS_CMD} -gt 80 ]; then
                            PROCESS_CMD="${PROCESS_CMD:0:77}..."
                        fi
                        log_message "ALERT" "  → Command: $PROCESS_CMD"
                    fi
                fi
            done
        fi
    done
    
    # Check for a high number of connections from a single process
    PROCESS_CONNECTIONS=$(lsof -i | grep -v LISTEN | awk '{print $1}' | sort | uniq -c | sort -nr)
    echo "$PROCESS_CONNECTIONS" | head -5 | while read -r line; do
        COUNT=$(echo "$line" | awk '{print $1}')
        PROCESS=$(echo "$line" | awk '{print $2}')
        
        # If a process has more than 20 connections, it might be worth investigating
        if [ "$COUNT" -gt 20 ]; then
            log_message "INFO" "Process $PROCESS has $COUNT connections - this may be normal but worth checking"
            
            # Get CPU usage for this process if top is available
            if command -v ps &> /dev/null; then
                # First try to get PID directly using pgrep with exact match
                PID=$(pgrep -x "$PROCESS" 2>/dev/null | head -1)
                
                # If that fails, try a more flexible approach with case-insensitive partial match
                if [ -z "$PID" ]; then
                    PID=$(pgrep -i "$PROCESS" 2>/dev/null | head -1)
                fi
                
                # If we found a PID, get its CPU usage
                if [ -n "$PID" ]; then
                    CPU_USAGE=$(ps -p "$PID" -o %cpu= 2>/dev/null | awk '{print $1}')
                    if [ -n "$CPU_USAGE" ]; then
                        log_message "INFO" "  → CPU usage: ${CPU_USAGE}%"
                    else
                        log_message "INFO" "  → CPU usage: Not available"
                    fi
                else
                    # If we couldn't get a PID, try using top as a fallback
                    if command -v top &> /dev/null; then
                        CPU_USAGE=$(top -l 1 -stats pid,command,cpu -o cpu | grep -i "$PROCESS" | head -1 | awk '{print $3}')
                        if [ -n "$CPU_USAGE" ]; then
                            # Extract only numeric part if it contains non-numeric characters
                            CPU_USAGE=$(echo "$CPU_USAGE" | grep -o '[0-9.]*')
                            if [ -n "$CPU_USAGE" ]; then
                                log_message "INFO" "  → CPU usage: ${CPU_USAGE}%"
                            else
                                log_message "INFO" "  → CPU usage: Not available"
                            fi
                        else
                            log_message "INFO" "  → CPU usage: Not available"
                        fi
                    else
                        log_message "INFO" "  → CPU usage: Not available"
                    fi
                fi
            else
                log_message "INFO" "  → CPU usage: Not available (ps command not found)"
            fi
        fi
    done
}

# Check for DNS leaks
check_dns_leaks() {
    log_message "INFO" "Checking for potential DNS leaks..."
    
    # Get configured DNS servers - fixed method
    CONFIGURED_DNS=$(scutil --dns | grep 'nameserver\[[0-9]*\]' | sort | uniq | awk '{print $3}')
    
    # Check what DNS servers are actually being used
    USED_DNS=$(scutil --dns | grep 'nameserver\[[0-9]*\]' | sort | uniq | awk '{print $3}')
    
    echo "--- DNS Servers Check at $(date) ---" >> "$LOG_FILE"
    echo "Configured DNS: $CONFIGURED_DNS" >> "$LOG_FILE"
    echo "Actually used DNS: $USED_DNS" >> "$LOG_FILE"
    echo "--- End of DNS Servers Check ---" >> "$LOG_FILE"
    
    # Check for DNS response times (can indicate DNS hijacking)
    log_message "INFO" "Testing DNS response times..."
    for domain in google.com apple.com cloudflare.com; do
        START_TIME=$(date +%s.%N)
        dig +short $domain > /dev/null 2>&1
        END_TIME=$(date +%s.%N)
        ELAPSED=$(echo "$END_TIME - $START_TIME" | bc)
        log_message "INFO" "DNS lookup for $domain took $ELAPSED seconds"
        
        # Only warn about slow responses - fast responses are normal due to caching
        if (( $(echo "$ELAPSED > 2.0" | bc -l) )); then
            log_message "WARNING" "Suspiciously slow DNS response time for $domain: $ELAPSED seconds"
        fi
    done
    
    # Check for DNS hijacking by comparing resolved IPs with known values
    log_message "INFO" "Checking for DNS hijacking..."
    GOOGLE_IP=$(dig +short google.com | head -1)
    if [ -n "$GOOGLE_IP" ]; then
        # Check if the IP is in Google's range (very basic check)
        if ! echo "$GOOGLE_IP" | grep -qE '^(172\.217\.|216\.58\.|142\.250\.|74\.125\.)'; then
            log_message "ALERT" "Possible DNS hijacking detected! google.com resolves to $GOOGLE_IP which is not in Google's IP range"
        fi
    fi
}

# Display network summary
display_network_summary() {
    log_message "INFO" "===== NETWORK SUMMARY ====="
    
    # Show active connections by destination
    log_message "INFO" "Active connections by destination:"
    netstat -an | grep ESTABLISHED | awk '{print $5}' | cut -d. -f1,2,3,4 | sort | uniq -c | sort -nr | head -5 | while read -r line; do
        COUNT=$(echo "$line" | awk '{print $1}')
        IP=$(echo "$line" | awk '{print $2}')
        # Try to get hostname
        HOST=$(dig +short -x $IP 2>/dev/null || echo "Unknown")
        log_message "INFO" "$COUNT connections to $IP ($HOST)"
    done
    
    # Show processes with network activity
    log_message "INFO" "Top processes with network activity:"
    lsof -i -P -n | grep -v LISTEN | awk '{print $1}' | sort | uniq -c | sort -nr | head -5 | while read -r line; do
        COUNT=$(echo "$line" | awk '{print $1}')
        PROCESS=$(echo "$line" | awk '{print $2}')
        log_message "INFO" "$PROCESS: $COUNT connections"
        
        # Get CPU usage for this process if top is available
        if command -v ps &> /dev/null; then
            # First try to get PID directly using pgrep with exact match
            PID=$(pgrep -x "$PROCESS" 2>/dev/null | head -1)
            
            # If that fails, try a more flexible approach with case-insensitive partial match
            if [ -z "$PID" ]; then
                PID=$(pgrep -i "$PROCESS" 2>/dev/null | head -1)
            fi
            
            # If we found a PID, get its CPU usage
            if [ -n "$PID" ]; then
                CPU_USAGE=$(ps -p "$PID" -o %cpu= 2>/dev/null | awk '{print $1}')
                if [ -n "$CPU_USAGE" ]; then
                    log_message "INFO" "  → CPU usage: ${CPU_USAGE}%"
                else
                    log_message "INFO" "  → CPU usage: Not available"
                fi
            else
                # If we couldn't get a PID, try using top as a fallback
                if command -v top &> /dev/null; then
                    CPU_USAGE=$(top -l 1 -stats pid,command,cpu -o cpu | grep -i "$PROCESS" | head -1 | awk '{print $3}')
                    if [ -n "$CPU_USAGE" ]; then
                        # Extract only numeric part if it contains non-numeric characters
                        CPU_USAGE=$(echo "$CPU_USAGE" | grep -o '[0-9.]*')
                        if [ -n "$CPU_USAGE" ]; then
                            log_message "INFO" "  → CPU usage: ${CPU_USAGE}%"
                        else
                            log_message "INFO" "  → CPU usage: Not available"
                        fi
                    else
                        log_message "INFO" "  → CPU usage: Not available"
                    fi
                else
                    log_message "INFO" "  → CPU usage: Not available"
                fi
            fi
        else
            log_message "INFO" "  → CPU usage: Not available (ps command not found)"
        fi
    done
    
    # Check for unusual protocols - improved to filter out common Unix domain sockets
    UNUSUAL=$(netstat -an | grep -v "tcp4\|tcp6\|udp4\|udp6\|icm" | grep -v "Active\|Proto" | grep -v "/private/tmp/com.apple" | grep -v "/var/run/" | grep -v "/private/var/run")
    if [ -n "$UNUSUAL" ]; then
        log_message "WARNING" "Unusual network protocols detected:"
        
        # Instead of trying to format the raw output, just report the count and log details to file
        UNUSUAL_COUNT=$(echo "$UNUSUAL" | wc -l | tr -d ' ')
        log_message "WARNING" "Found $UNUSUAL_COUNT unusual protocol connections (details in log file)"
        
        # Log the full details to the log file only
        echo "--- Unusual Network Protocols at $(date) ---" >> "$LOG_FILE"
        echo "$UNUSUAL" >> "$LOG_FILE"
        echo "--- End of Unusual Network Protocols ---" >> "$LOG_FILE"
    fi
    
    # Show system load
    if command -v uptime &> /dev/null; then
        LOAD=$(uptime | awk -F'load averages:' '{print $2}')
        log_message "INFO" "System load averages:$LOAD"
    fi
    
    log_message "INFO" "===== END OF SUMMARY ====="
}

# Monitor active connections
monitor_connections() {
    log_message "INFO" "Monitoring active connections..."
    
    # Get baseline of current connections
    PREV_CONNECTIONS=$(netstat -an | grep ESTABLISHED | wc -l | tr -d ' ')
    log_message "INFO" "Current established connections: $PREV_CONNECTIONS"
    
    while true; do
        # Get current connections
        CURRENT_CONNECTIONS=$(netstat -an | grep ESTABLISHED | wc -l | tr -d ' ')
        
        # Adjust threshold based on known/unknown network
        # Increased thresholds to reduce false positives
        THRESHOLD=10
        if [ "$KNOWN_NETWORK" = false ]; then
            THRESHOLD=5
        fi
        
        # Check for significant increase in connections
        if (( CURRENT_CONNECTIONS > PREV_CONNECTIONS + THRESHOLD )); then
            log_message "ALERT" "Sudden increase in connections: $PREV_CONNECTIONS → $CURRENT_CONNECTIONS"
            # Log the connections
            echo "--- Established Connections at $(date) ---" >> "$LOG_FILE"
            netstat -an | grep ESTABLISHED >> "$LOG_FILE"
            echo "--- End of Connections List ---" >> "$LOG_FILE"
        fi
        
        # Check for suspicious connection attempts
        CONN_ATTEMPTS=$(netstat -an | grep SYN_RECV 2>/dev/null)
        if [[ -n "$CONN_ATTEMPTS" ]]; then
            log_message "WARNING" "Detected connection attempts"
            echo "--- Connection Attempts at $(date) ---" >> "$LOG_FILE"
            echo "$CONN_ATTEMPTS" >> "$LOG_FILE"
            echo "--- End of Connection Attempts ---" >> "$LOG_FILE"
        fi
        
        # Update previous connections count
        PREV_CONNECTIONS=$CURRENT_CONNECTIONS
        
        # Sleep for a bit before checking again
        sleep $CONNECTION_CHECK_INTERVAL
    done
}

# Check for ARP spoofing (common on public WiFi)
check_arp_spoofing() {
    log_message "INFO" "Checking for potential ARP spoofing..."
    
    # Get the MAC address of the default gateway
    GATEWAY_IP=$(netstat -rn | grep default | head -1 | awk '{print $2}')
    
    if [ -z "$GATEWAY_IP" ]; then
        log_message "WARNING" "Could not determine gateway IP. Skipping ARP spoofing detection."
        return
    fi
    
    GATEWAY_MAC=$(arp -a | grep "$GATEWAY_IP" | awk '{print $4}')
    
    if [ -z "$GATEWAY_MAC" ]; then
        log_message "WARNING" "Could not determine gateway MAC address. Skipping ARP spoofing detection."
        return
    fi
    
    log_message "INFO" "Default gateway ($GATEWAY_IP) has MAC: $GATEWAY_MAC"
    
    # Monitor for changes in the gateway's MAC address
    while true; do
        CURRENT_MAC=$(arp -a | grep "$GATEWAY_IP" | awk '{print $4}')
        
        if [[ -n "$CURRENT_MAC" && -n "$GATEWAY_MAC" && "$CURRENT_MAC" != "$GATEWAY_MAC" ]]; then
            log_message "ALERT" "Possible ARP spoofing detected! Gateway MAC changed from $GATEWAY_MAC to $CURRENT_MAC"
            GATEWAY_MAC=$CURRENT_MAC
        fi
        
        sleep $ARP_CHECK_INTERVAL
    done
}

# Periodic port check
periodic_port_check() {
    while true; do
        # Only run full port check periodically to reduce resource usage
        sleep $PORT_CHECK_INTERVAL
        check_open_ports
    done
}

# Show menu
show_menu() {
    echo -e "\n${BLUE}=========================================================${NC}"
    echo -e "${BLUE}                      MENU OPTIONS                       ${NC}"
    echo -e "${BLUE}=========================================================${NC}"
    echo -e "1) Start monitoring (normal mode)"
    echo -e "2) Start monitoring (low resource usage)"
    echo -e "3) Quick scan (one-time check)"
    echo -e "4) View connection history"
    echo -e "5) View current log file"
    echo -e "6) Exit"
    echo -e "${YELLOW}Enter your choice [1-6]:${NC}"
    read -r choice
    
    case $choice in
        1)
            start_monitoring "normal"
            ;;
        2)
            start_monitoring "low"
            ;;
        3)
            quick_scan
            show_menu
            ;;
        4)
            view_connection_history
            show_menu
            ;;
        5)
            if [ -f "$LOG_FILE" ]; then
                less "$LOG_FILE" | cat
                show_menu
            else
                echo -e "${RED}No log file found. Start monitoring first.${NC}"
                show_menu
            fi
            ;;
        6)
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please try again.${NC}"
            show_menu
            ;;
    esac
}

# Quick scan mode - run a one-time check without continuous monitoring
quick_scan() {
    echo -e "${CYAN}Running quick scan...${NC}"
    
    # Get network information
    get_network_info
    
    # Display network summary
    display_network_summary
    
    # Check open ports
    check_open_ports
    
    # Check for DNS leaks
    check_dns_leaks
    
    # Investigate unusual connections
    investigate_unusual_connections
    
    # Track connection history
    track_connection_history
    
    echo -e "${CYAN}Quick scan complete. Results saved to $LOG_FILE${NC}"
}

# View connection history
view_connection_history() {
    if [ -f "$HISTORY_FILE" ]; then
        echo -e "${CYAN}Connection History:${NC}"
        echo -e "${CYAN}------------------${NC}"
        
        # Display formatted connection history
        awk -F, 'NR>2 {print "\033[0;32m" $1 "\033[0m - Network: \033[0;33m" $2 "\033[0m, Local IP: " $3 ", Public IP: " $4}' "$HISTORY_FILE" | tail -10
        
        # Check for network changes
        NETWORKS=$(awk -F, 'NR>2 {print $2}' "$HISTORY_FILE" | sort | uniq | wc -l | tr -d ' ')
        if [ "$NETWORKS" -gt 1 ]; then
            echo -e "${YELLOW}Multiple networks detected in history (total: $NETWORKS)${NC}"
            echo -e "${YELLOW}Networks used:${NC}"
            awk -F, 'NR>2 {print $2}' "$HISTORY_FILE" | sort | uniq -c | sort -nr | while read -r count network; do
                echo -e "  ${YELLOW}$network${NC}: $count times"
            done
        fi
        
        # Check for public IP changes
        PUBLIC_IPS=$(awk -F, 'NR>2 {print $4}' "$HISTORY_FILE" | sort | uniq | wc -l | tr -d ' ')
        if [ "$PUBLIC_IPS" -gt 1 ]; then
            echo -e "${YELLOW}Public IP changes detected (total: $PUBLIC_IPS different IPs)${NC}"
        fi
    else
        echo -e "${RED}No connection history found. Start monitoring first.${NC}"
    fi
}

# Start monitoring
start_monitoring() {
    local mode="$1"
    
    # Get initial network information
    get_network_info
    
    # Track connection history
    track_connection_history
    
    # Display network summary
    display_network_summary
    
    # Check open ports
    check_open_ports
    
    # Check for DNS leaks
    check_dns_leaks
    
    # Investigate unusual connections
    investigate_unusual_connections
    
    # Set trap for graceful termination
    trap cleanup INT TERM EXIT HUP
    
    if [ "$mode" = "normal" ]; then
        log_message "INFO" "Starting monitoring in normal mode"
        
        # Start monitoring in background
        monitor_connections &
        MONITOR_PID=$!
        
        # Start ARP spoofing detection in background
        check_arp_spoofing &
        ARP_PID=$!
        
        # Start periodic port checking
        periodic_port_check &
        PORT_PID=$!
        
        # Start traffic volume monitoring
        monitor_traffic_volume &
        TRAFFIC_PID=$!
    else
        log_message "INFO" "Starting monitoring in low resource usage mode"
        
        # Increase intervals to reduce resource usage
        CONNECTION_CHECK_INTERVAL=30
        ARP_CHECK_INTERVAL=60
        TRAFFIC_CHECK_INTERVAL=120
        
        # Start monitoring in background
        monitor_connections &
        MONITOR_PID=$!
        
        # Start ARP spoofing detection in background
        check_arp_spoofing &
        ARP_PID=$!
        
        # Start traffic volume monitoring with reduced frequency
        monitor_traffic_volume &
        TRAFFIC_PID=$!
    fi
    
    log_message "INFO" "Monitoring started. Press Ctrl+C to stop."
    
    # Keep script running but check periodically if processes are still alive
    while true; do
        if [ -n "$MONITOR_PID" ] && ! kill -0 $MONITOR_PID 2>/dev/null; then
            log_message "WARNING" "Connection monitoring process died unexpectedly. Restarting..."
            monitor_connections &
            MONITOR_PID=$!
        fi
        
        if [ -n "$ARP_PID" ] && ! kill -0 $ARP_PID 2>/dev/null; then
            log_message "WARNING" "ARP spoofing detection process died unexpectedly. Restarting..."
            check_arp_spoofing &
            ARP_PID=$!
        fi
        
        if [ "$mode" = "normal" ] && [ -n "$PORT_PID" ] && ! kill -0 $PORT_PID 2>/dev/null; then
            log_message "WARNING" "Port checking process died unexpectedly. Restarting..."
            periodic_port_check &
            PORT_PID=$!
        fi
        
        if [ -n "$TRAFFIC_PID" ] && ! kill -0 $TRAFFIC_PID 2>/dev/null; then
            log_message "WARNING" "Traffic monitoring process died unexpectedly. Restarting..."
            monitor_traffic_volume &
            TRAFFIC_PID=$!
        fi
        
        # Periodically display network summary (every 5 minutes)
        if (( $(date +%s) % 300 < 2 )); then
            display_network_summary
            investigate_unusual_connections
            sleep 2  # Avoid multiple executions in the same second
        fi
        
        sleep 30
    done
}

# Clean up function
cleanup() {
    log_message "INFO" "Stopping monitoring..."
    
    # Kill any background processes
    if [ -n "$MONITOR_PID" ]; then
        kill $MONITOR_PID 2>/dev/null || true
    fi
    
    if [ -n "$ARP_PID" ]; then
        kill $ARP_PID 2>/dev/null || true
    fi
    
    if [ -n "$PORT_PID" ]; then
        kill $PORT_PID 2>/dev/null || true
    fi
    
    if [ -n "$TRAFFIC_PID" ]; then
        kill $TRAFFIC_PID 2>/dev/null || true
    fi
    
    log_message "INFO" "Monitoring stopped. Log file: $LOG_FILE"
    exit 0
}

# Process command line arguments
process_args() {
    # Check if the argument is a number (for backward compatibility)
    if [[ $1 =~ ^[0-9]+$ ]]; then
        case "$1" in
            1)
                print_banner
                start_monitoring "normal"
                exit 0
                ;;
            2)
                print_banner
                start_monitoring "low"
                exit 0
                ;;
            3)
                print_banner
                quick_scan
                exit 0
                ;;
            4)
                print_banner
                view_connection_history
                exit 0
                ;;
            5)
                print_banner
                if [ -f "$LOG_FILE" ]; then
                    less "$LOG_FILE" | cat
                else
                    echo -e "${RED}No log file found. Start monitoring first.${NC}"
                fi
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid numeric option: $1${NC}"
                print_usage
                exit 1
                ;;
        esac
    fi
    
    # If no arguments provided, default to quick scan
    if [ $# -eq 0 ]; then
        print_banner
        quick_scan
        exit 0
    fi
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--normal)
                print_banner
                start_monitoring "normal"
                exit 0
                ;;
            -l|--low)
                print_banner
                start_monitoring "low"
                exit 0
                ;;
            -q|--quick)
                print_banner
                quick_scan
                exit 0
                ;;
            -c|--connections)
                print_banner
                view_connection_history
                exit 0
                ;;
            -f|--file)
                print_banner
                if [ -f "$LOG_FILE" ]; then
                    less "$LOG_FILE" | cat
                else
                    echo -e "${RED}No log file found. Start monitoring first.${NC}"
                fi
                exit 0
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                print_usage
                exit 1
                ;;
        esac
        shift
    done
}

# Main execution
# Check if arguments were provided
if [ $# -gt 0 ]; then
    # Process command line arguments
    process_args "$@"
else
    # Show menu to start (interactive mode)
    print_banner
    set +e
    show_menu
fi 