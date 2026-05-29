#!/usr/bin/env bash
# Vaultwarden CLI wrapper — pre-configured for the self-hosted instance at
# warden.leopaska.xyz. Delegates to the in-repo helper so updates land in git.
#
# Usage examples:
#   vw login                      # interactive login
#   eval "$(vw unlock)"           # exports BW_SESSION for this shell
#   vw status
#   vw sync
#   vw import bitwardencsv ~/Downloads/lastpass.csv
#   vw -- list items              # raw bw passthrough

set -euo pipefail
HOMELAB_DIR="${HOMELAB_DIR:-$HOME/git/homelab}"
exec "${HOMELAB_DIR}/scripts/vaultwarden/bw-helper.sh" "$@"
