#!/usr/bin/env bash
# One-shot bootstrap for the Google Workspace Terraform stack.
# Idempotent — safe to re-run.
#
# What it does:
#   1. Verifies gcloud + gam7 + terraform are available
#   2. Creates the GCP service account + key for the googleworkspace provider
#      (calls scripts/workspace/bootstrap-sa.sh)
#   3. Prints the DWD client_id + scopes you need to paste into
#      admin.google.com (this UI step has no API surface — Google's choice)
#   4. Reminds you to copy terraform.auto.tfvars.example and fill it in
#
# Usage:  homelab-email-bootstrap

set -euo pipefail
HOMELAB_DIR="${HOMELAB_DIR:-$HOME/git/homelab}"
exec "${HOMELAB_DIR}/scripts/workspace/bootstrap-sa.sh" "$@"
