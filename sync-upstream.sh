#!/usr/bin/env bash
# sync-upstream — pull the creator's upstream into a customized fork while
# keeping our local changes, then push to origin (Forgejo, which mirrors to
# GitHub). This is the uniform paradigm for every agent/harness fork.
#
# Three-remote model each fork is expected to have:
#   origin    -> Forgejo  (git@git.leopaska.xyz:leo/<repo>.git, push via
#                          ssh://git@git-ssh.leopaska.xyz/leo/<repo>.git)
#                our customized fork — the central copy.
#   github    -> GitHub   (git@github.com:l3ocifer/<repo>.git) backup mirror
#                (Forgejo push-mirror keeps it current; we also push best-effort).
#   upstream  -> creator  (e.g. git@github.com:nearai/ironclaw.git) READ-ONLY
#                source of upstream changes.
#
# Usage:
#   sync-upstream                 # merge upstream's default branch into current branch
#   sync-upstream -b main         # target a specific local branch
#   sync-upstream -u master       # override the upstream branch to merge
#   sync-upstream --keep          # on conflict, leave merge markers to resolve
#                                 #   (default: abort cleanly so nothing is half-merged)
#   sync-upstream --no-push       # don't push after a clean merge
#
# Env:
#   GIT_PUSH_TIMEOUT   seconds per network op (default 180)

set -uo pipefail

err()  { printf '\033[1;31m[sync-upstream:err]\033[0m %s\n' "$1" >&2; }
log()  { printf '\033[1;34m[sync-upstream]\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m[sync-upstream]\033[0m %s\n' "$1"; }

target_branch=""
upstream_branch=""
keep_conflicts=0
do_push=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--branch)   target_branch="${2:-}"; shift 2 ;;
    -u|--upstream) upstream_branch="${2:-}"; shift 2 ;;
    --keep)        keep_conflicts=1; shift ;;
    --no-push)     do_push=0; shift ;;
    -h|--help)     sed -n '2,40p' "$0"; exit 0 ;;
    *)             err "unknown arg: $1"; exit 1 ;;
  esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { err "not inside a git repository"; exit 1; }
cd "$(git rev-parse --show-toplevel)" || exit 1

git remote get-url upstream >/dev/null 2>&1 || {
  err "no 'upstream' remote — this repo is not set up as a fork."
  err "add one:  git remote add upstream <creator-repo-url>"; exit 1; }

# Refuse to merge on a dirty tree (protects uncommitted local work).
if [[ -n "$(git status --porcelain)" ]]; then
  err "working tree is dirty — commit or stash before syncing upstream."; exit 1
fi

cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[[ -z "$target_branch" ]] && target_branch="$cur"
if [[ "$target_branch" != "$cur" ]]; then
  git checkout "$target_branch" || { err "cannot checkout $target_branch"; exit 1; }
fi

TIMEOUT="${GIT_PUSH_TIMEOUT:-180}"
run() {
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$TIMEOUT" git "$@"
  elif command -v timeout >/dev/null 2>&1; then timeout "$TIMEOUT" git "$@"
  else git "$@"; fi
}

log "fetching upstream…"
run fetch upstream --prune || { err "upstream fetch failed (timeout/auth?)"; exit 1; }

# Resolve the upstream branch to merge.
if [[ -z "$upstream_branch" ]]; then
  upstream_branch=$(git remote show upstream 2>/dev/null | sed -n 's/.*HEAD branch: //p')
  upstream_branch="${upstream_branch:-main}"
fi
git rev-parse --verify -q "upstream/$upstream_branch" >/dev/null 2>&1 || {
  err "upstream/$upstream_branch does not exist after fetch"; exit 1; }

behind=$(git rev-list --count "$target_branch..upstream/$upstream_branch" 2>/dev/null)
ahead=$(git rev-list --count "upstream/$upstream_branch..$target_branch" 2>/dev/null)
log "$target_branch is behind upstream/$upstream_branch by ${behind:-?} (our custom commits ahead: ${ahead:-?})"
if [[ "${behind:-0}" == "0" ]]; then
  log "already up to date with upstream — nothing to merge."
  [[ $do_push -eq 1 ]] && { log "pushing to keep remotes current…"; run push origin "$target_branch" 2>/dev/null || true; run push github "$target_branch" 2>/dev/null || true; }
  exit 0
fi

log "merging upstream/$upstream_branch into $target_branch…"
if git merge --no-edit "upstream/$upstream_branch"; then
  log "merged cleanly -> $(git rev-parse --short HEAD)"
  if [[ $do_push -eq 1 ]]; then
    run push origin "$target_branch" || { err "push to origin failed"; exit 1; }
    log "pushed to origin (Forgejo)"
    if git remote get-url github >/dev/null 2>&1; then
      run push github "$target_branch" 2>/dev/null && log "mirrored to github backup" \
        || log "github not updated (Forgejo push-mirror will sync it)"
    fi
  fi
  log "done"
else
  nconf=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l | tr -d ' ')
  warn "merge conflicts in $nconf file(s):"
  git diff --name-only --diff-filter=U 2>/dev/null | sed 's/^/    /'
  if [[ $keep_conflicts -eq 1 ]]; then
    warn "left in conflicted state (--keep). Resolve, 'git add' the files, then:"
    warn "  git commit && sync-upstream --no-push is not needed — just 'commit' to push."
    exit 2
  else
    git merge --abort
    err "aborted — no changes made. Re-run with --keep to resolve in place, or"
    err "resolve on a branch:  git checkout -b sync/upstream-\$(date +%Y%m%d) && git merge upstream/$upstream_branch"
    exit 2
  fi
fi
