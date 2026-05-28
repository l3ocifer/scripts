#!/usr/bin/env bash
# commit — stage everything, commit, and push, working uniformly across all our
# repos regardless of forge layout.
#
# Model: Forgejo is the central origin; GitHub is a backup/mirror. Pushing to
# `origin` is always correct:
#   - forgejo-primary repos  -> origin = Forgejo; Forgejo push-mirrors to GitHub.
#   - legacy github repos    -> origin = GitHub.
# If a separate `github` remote exists alongside a Forgejo origin we also push
# it best-effort so the backup is immediately current (non-fatal on failure).
#
# Usage:
#   commit                 # prompt for message (default "updated")
#   commit "fix: message"  # non-interactive, use given message
#   commit -m "message"    # same
#
# Env:
#   GIT_PUSH_TIMEOUT  seconds to allow each push before giving up (default 60)

set -uo pipefail

err() { printf '\033[1;31m[commit:err]\033[0m %s\n' "$1" >&2; }
log() { printf '\033[1;34m[commit]\033[0m %s\n' "$1"; }

# Must be inside a work tree.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  err "not inside a git repository"; exit 1
fi
# Operate from the repo root so `git add -A` is unambiguous.
cd "$(git rev-parse --show-toplevel)" || exit 1

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
  err "detached HEAD; checkout a branch before committing"; exit 1
fi

# Resolve commit message: arg > -m arg > interactive prompt > default.
msg=""
case "${1:-}" in
  -m) msg="${2:-}" ;;
  "") ;;
  *)  msg="$1" ;;
esac
if [[ -z "$msg" ]]; then
  default_message="updated"
  if [[ -t 0 ]]; then
    read -r -p "Enter commit message (default: $default_message): " msg
  fi
  msg="${msg:-$default_message}"
fi

TIMEOUT="${GIT_PUSH_TIMEOUT:-60}"
run_push() {
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$TIMEOUT" git "$@"
  elif command -v timeout >/dev/null 2>&1; then timeout "$TIMEOUT" git "$@"
  else git "$@"; fi
}

# Stage + commit (skip cleanly when there is nothing new to record).
git add -A
if git diff --cached --quiet; then
  log "no staged changes; checking for unpushed commits"
else
  git commit -m "$msg" || { err "commit failed (pre-commit hook?)"; exit 1; }
  log "committed: $(git rev-parse --short HEAD) — $msg"
fi

# Push to origin, creating the upstream ref on first push.
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  if [[ -z "$(git log '@{u}'..HEAD 2>/dev/null)" ]]; then
    log "origin already up to date"
  else
    log "pushing to origin ($branch)"
    run_push push origin "$branch" || { err "push to origin failed"; exit 1; }
  fi
else
  log "no upstream set; pushing -u origin $branch"
  run_push push -u origin "$branch" || { err "push to origin failed"; exit 1; }
fi

# Best-effort: keep an explicit GitHub backup remote current if one exists and
# origin is NOT already GitHub (otherwise it's the same push).
if git remote get-url github >/dev/null 2>&1; then
  origin_url=$(git remote get-url origin 2>/dev/null)
  if [[ "$origin_url" != *github.com* ]]; then
    if run_push push github "$branch" 2>/dev/null; then
      log "mirrored to github backup remote"
    else
      log "github backup remote not updated (Forgejo push-mirror will sync it)"
    fi
  fi
fi

log "done"
