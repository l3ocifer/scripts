#!/bin/bash

# Stop Parallels-related processes
killall prl_client_app
killall prl_disp_service
killall Parallels

# Remove Parallels application
sudo rm -rf /Applications/Parallels\ Desktop.app

# Remove Parallels preferences
rm -rf ~/Library/Preferences/com.parallels.*
rm -rf ~/Library/Preferences/Parallels

# Remove Parallels support files
sudo rm -rf /Library/Parallels
rm -rf ~/Library/Parallels
rm -rf ~/Library/Logs/parallels*
rm -rf ~/Library/Saved\ Application\ State/com.parallels.*

# Remove Parallels kernel extensions
sudo rm -rf /Library/Extensions/prl*
sudo rm -rf /System/Library/Extensions/prl*

# Remove Parallels launch agents and daemons
sudo rm -f /Library/LaunchDaemons/com.parallels.*
sudo rm -f /Library/LaunchAgents/com.parallels.*
rm -f ~/Library/LaunchAgents/com.parallels.*

# Remove Parallels receipts
sudo rm -rf /Library/Receipts/com.parallels.*

# Unload Parallels kernel extensions (if any are still loaded)
sudo kextunload -b com.parallels.kext.vnic
sudo kextunload -b com.parallels.kext.netbridge
sudo kextunload -b com.parallels.kext.hypervisor

# Clean up any remaining Parallels files (this might
