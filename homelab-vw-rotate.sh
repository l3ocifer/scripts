#!/usr/bin/env bash
# Rotates the Vaultwarden ADMIN_TOKEN end-to-end:
#   1. mints a new plaintext + Argon2-hash
#   2. seals it into argocd/sealed-secrets/vaultwarden-admin.yaml
#   3. patches the live Secret + restarts the Vaultwarden deployment
#   4. copies the new plaintext to the macOS clipboard
#
# Usage:  vw-rotate
# Then:   git add ... && git commit && git push   # so ArgoCD doesn't drift back

set -euo pipefail
HOMELAB_DIR="${HOMELAB_DIR:-$HOME/git/homelab}"
exec "${HOMELAB_DIR}/scripts/vaultwarden/rotate-admin-token.sh" "$@"
