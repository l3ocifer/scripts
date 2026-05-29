#!/usr/bin/env bash
# Wrapper that delegates to the homelab repo's add-domain runner so future
# updates land in git, not on disk.
#
# Usage:  add-email-domain newbrand.com
#
# Edits required before running:
#   ~/git/homelab/terraform/workspace/terraform.auto.tfvars
#       Add the new domain under brand_domains. See the example file or
#       docs/email-domain-onboarding.md.
#
# After running:
#   The script prints the verification token + DKIM key to paste back
#   into the same tfvars file, then asks you to re-run `terraform apply`.

set -euo pipefail
HOMELAB_DIR="${HOMELAB_DIR:-$HOME/git/homelab}"
exec "${HOMELAB_DIR}/scripts/workspace/add-domain.sh" "$@"
