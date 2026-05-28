#!/usr/bin/env bash
# newrepo — create a new git repo with the agent-readiness baseline already applied.
#
# Defaults to Forgejo as the central origin + GitHub as a backup/mirror:
# Forgejo is `origin`, GitHub is the `github` remote, and Forgejo is configured
# to push-mirror to GitHub on every commit. Requires FORGEJO_TOKEN (env or a
# 'Forgejo API Token (leo)' Vaultwarden login); without it, falls back to
# GitHub-primary with a warning. Use --no-forgejo or --github-primary to opt out.
#
# Interactive by default; pass flags or --yes for scripted/agent use.
#
# Usage:
#   newrepo                                          # full interactive (Forgejo-central)
#   newrepo --here                                   # use current dir as the repo
#   newrepo myproj --subdir agents --tier hot \
#           --stack rust --visibility private --branch main
#   newrepo myproj --github-primary                  # GitHub origin, Forgejo as 'forgejo' remote
#   newrepo myproj --no-forgejo                      # GitHub only (legacy)
#
# Flags:
#   --name <n>             repo name (basename in github + filesystem)
#   --here                 use current dir; --name overrides folder name
#   --subdir <d>           place inside ~/git/<d>/ (default: ~/git)
#   --owner-org <org>      create under github org (default: personal user)
#   --visibility <v>       public | private (default: private)
#   --branch <b>           default branch (default: main)
#   --tier <t>             hot | warm | cold (default: warm)
#   --stack "<s>"          free-form stack label
#   --description "<d>"    github description
#   --no-register          skip appending to ~/git/templates/repos.yaml
#   --no-protect           skip applying branch protection at the end
#   --no-push              skip remote create + push (both forges)
#   --forgejo              force-enable Forgejo creation (on by default)
#   --forgejo-primary      Forgejo is origin (default); GitHub is the 'github'
#                          remote, with a Forgejo->GitHub push mirror
#   --no-forgejo           skip Forgejo entirely; GitHub-only (legacy behaviour)
#   --github-primary       GitHub is origin; Forgejo added as the 'forgejo' remote
#   --no-github            skip GitHub creation entirely (Forgejo-only)
#   --yes                  non-interactive; fail if a required field is missing
#   -h, --help             print this and exit
#
# Env (Forgejo):
#   FORGEJO_URL            default: https://git.leopaska.xyz
#   FORGEJO_OWNER          default: leo
#   FORGEJO_TOKEN          required when --forgejo or --forgejo-primary is set

set -euo pipefail

GIT_HOME="${GIT_HOME:-$HOME/git}"
TEMPLATES="${TEMPLATES:-$GIT_HOME/templates}"
BOOTSTRAP="$TEMPLATES/scripts/bootstrap-agent-readiness.sh"
PROTECT="$TEMPLATES/scripts/apply-branch-protection.sh"
REGISTRY="$TEMPLATES/repos.yaml"

usage() { sed -n '2,45p' "$0"; exit "${1:-0}"; }

# defaults — Forgejo is central, GitHub is the backup/mirror.
name=""
here=0
subdir=""
owner_org=""
visibility="private"
branch="main"
tier="warm"
stack=""
description=""
register=1
protect=1
push=1
yes=0
forgejo=1
forgejo_primary=1
github=1
FORGEJO_URL="${FORGEJO_URL:-https://git.leopaska.xyz}"
FORGEJO_OWNER="${FORGEJO_OWNER:-leo}"
# Forgejo SSH endpoints (Cloudflare TCP tunnel): fetch via git@<host>, push via
# ssh://git@git-ssh.<domain>. Override with FORGEJO_SSH_* if your setup differs.
FORGEJO_SSH_FETCH_HOST="${FORGEJO_SSH_FETCH_HOST:-git.leopaska.xyz}"
FORGEJO_SSH_PUSH_HOST="${FORGEJO_SSH_PUSH_HOST:-git-ssh.leopaska.xyz}"
# Reuse an existing GitHub admin PAT for the Forgejo->GitHub push mirror.
FORGEJO_GH_MIRROR_PAT="${FORGEJO_GH_MIRROR_PAT:-${GITHUB_ACCESS_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}}"

# accept first positional arg as the name
if [[ ${#@} -gt 0 && "${1:0:1}" != "-" ]]; then
  name="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) name="$2"; shift 2 ;;
    --here) here=1; shift ;;
    --subdir) subdir="$2"; shift 2 ;;
    --owner-org) owner_org="$2"; shift 2 ;;
    --visibility) visibility="$2"; shift 2 ;;
    --branch) branch="$2"; shift 2 ;;
    --tier) tier="$2"; shift 2 ;;
    --stack) stack="$2"; shift 2 ;;
    --description) description="$2"; shift 2 ;;
    --no-register) register=0; shift ;;
    --no-protect) protect=0; shift ;;
    --no-push) push=0; shift ;;
    --forgejo) forgejo=1; shift ;;
    --forgejo-primary) forgejo=1; forgejo_primary=1; shift ;;
    --no-forgejo) forgejo=0; forgejo_primary=0; shift ;;
    --github-primary) forgejo_primary=0; shift ;;
    --no-github) github=0; shift ;;
    --yes|-y) yes=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "unknown flag: $1" >&2; usage 2 ;;
  esac
done

# ── helpers ────────────────────────────────────────────────────────────────
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$1" "$2"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$1" >&2; }
err()  { printf '\033[1;31m[err]\033[0m %s\n' "$1" >&2; }

ask() {
  local prompt="$1" default="${2:-}" var
  if [[ $yes -eq 1 ]]; then printf '%s' "$default"; return; fi
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " var
    printf '%s' "${var:-$default}"
  else
    read -r -p "$prompt: " var
    printf '%s' "$var"
  fi
}

ask_choice() {
  local prompt="$1" default="$2"; shift 2
  local options=("$@")
  if [[ $yes -eq 1 ]]; then printf '%s' "$default"; return; fi
  echo "$prompt" >&2
  local i=1
  for o in "${options[@]}"; do
    if [[ "$o" == "$default" ]]; then echo "  $i) $o (default)" >&2
    else echo "  $i) $o" >&2; fi
    i=$((i+1))
  done
  local var
  read -r -p "Choose [default: $default]: " var
  if [[ -z "$var" ]]; then printf '%s' "$default"; return; fi
  if [[ "$var" =~ ^[0-9]+$ ]] && (( var >= 1 && var <= ${#options[@]} )); then
    printf '%s' "${options[$((var-1))]}"
  else
    printf '%s' "$var"
  fi
}

need git
need gh

# ── resolve repo location + name ───────────────────────────────────────────
if [[ $here -eq 1 ]]; then
  repo_root="$(pwd)"
  [[ -z "$name" ]] && name="$(basename "$repo_root" | sed 's/^\.//')"
  case "$repo_root/" in
    "$GIT_HOME"/*) ;;
    *) err "--here is only supported when pwd is under \$GIT_HOME ($GIT_HOME); current pwd: $repo_root"; exit 2 ;;
  esac
else
  if [[ -z "$name" ]]; then
    name=$(ask "Repository name")
    [[ -z "$name" ]] && { err "name required"; exit 2; }
  fi
  if [[ -z "$subdir" ]]; then
    if [[ $yes -eq 1 ]]; then
      subdir=""
    else
      mapfile -t subdirs < <(find "$GIT_HOME" -mindepth 1 -maxdepth 1 -type d -not -name '.*' -exec basename {} \; | sort)
      subdirs+=("(none — place at ~/git/$name)" "Create new subdirectory")
      pick=$(ask_choice "Place inside which subdirectory of ~/git ?" "(none — place at ~/git/$name)" "${subdirs[@]}")
      case "$pick" in
        "(none — place at ~/git/$name)") subdir="" ;;
        "Create new subdirectory")
          subdir=$(ask "New subdirectory name (under ~/git)")
          ;;
        *) subdir="$pick" ;;
      esac
    fi
  fi
  if [[ -n "$subdir" ]]; then
    repo_root="$GIT_HOME/$subdir/$name"
  else
    repo_root="$GIT_HOME/$name"
  fi
  if [[ -e "$repo_root" ]]; then
    err "$repo_root already exists; refusing to clobber"; exit 2
  fi
  mkdir -p "$repo_root"
fi

# ── interactively fill remaining metadata ─────────────────────────────────
if [[ $yes -eq 0 ]]; then
  visibility=$(ask_choice "Visibility" "$visibility" private public)
  branch=$(ask "Default branch" "$branch")
  tier=$(ask_choice "Tier" "$tier" hot warm cold)
  [[ -z "$stack" ]] && stack=$(ask "Stack label (e.g. 'next.js / typescript', 'rust', 'python')" "")
  [[ -z "$description" ]] && description=$(ask "Short github description" "")
  if [[ -z "$owner_org" ]]; then
    owner_org=$(ask "GitHub owner (leave blank for your personal account)" "")
  fi
fi

# normalize
case "$visibility" in private|public) ;; *) err "visibility must be private|public"; exit 2 ;; esac
case "$tier" in hot|warm|cold) ;; *) err "tier must be hot|warm|cold"; exit 2 ;; esac

# resolve forge identities
gh_slug=""
fj_slug=""
if [[ $github -eq 1 ]]; then
  gh_user=$(gh api user --jq .login 2>/dev/null || true)
  [[ -z "$gh_user" ]] && { err "gh not authenticated; run 'gh auth login' (or pass --no-github)"; exit 1; }
  gh_slug="${owner_org:-$gh_user}/$name"
fi
if [[ $forgejo -eq 1 ]]; then
  # Try to load FORGEJO_TOKEN from Vaultwarden if not already in the env.
  if [[ -z "${FORGEJO_TOKEN:-}" ]] && command -v bw >/dev/null 2>&1; then
    if [[ "$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null)" == "unlocked" ]]; then
      FORGEJO_TOKEN="$(bw get password 'Forgejo API Token (leo)' 2>/dev/null || true)"
      [[ -n "$FORGEJO_TOKEN" ]] && log "forgejo" "loaded FORGEJO_TOKEN from Vaultwarden"
    fi
  fi
  if [[ -z "${FORGEJO_TOKEN:-}" ]]; then
    if [[ $github -eq 1 ]]; then
      warn "FORGEJO_TOKEN not set (and not in unlocked Vaultwarden) — falling back to GitHub-primary."
      warn "Set FORGEJO_TOKEN (or add a 'Forgejo API Token (leo)' Vaultwarden login) to make Forgejo central."
      forgejo=0; forgejo_primary=0
    else
      err "FORGEJO_TOKEN required for Forgejo creation (no --no-forgejo and --no-github given)"; exit 1
    fi
  else
    fj_slug="$FORGEJO_OWNER/$name"
  fi
fi

# Slug recorded in the registry: prefer GitHub when present, since
# apply-branch-protection.sh + most agent tooling currently target GitHub.
# The Forgejo slug lives in its own field on the registry entry.
if [[ -n "$gh_slug" ]]; then slug="$gh_slug"
elif [[ -n "$fj_slug" ]]; then slug="$fj_slug"
else slug=""
fi
rel_path="${repo_root#$GIT_HOME/}"

log "newrepo" "name=$name path=$repo_root tier=$tier branch=$branch"
[[ -n "$gh_slug" ]] && log "newrepo" "github=$gh_slug visibility=$visibility"
[[ -n "$fj_slug" ]] && log "newrepo" "forgejo=$fj_slug primary=$forgejo_primary"

# ── git init + initial README ─────────────────────────────────────────────
cd "$repo_root"
if [[ ! -d .git ]]; then
  git init -b "$branch" >/dev/null
fi

if [[ ! -f README.md ]]; then
  {
    printf '# %s\n\n' "$name"
    [[ -n "$description" ]] && printf '%s\n\n' "$description"
    printf '## Quick start\n\n'
    printf '```bash\n'
    printf '# install\n# dev\n# test\n'
    printf '```\n\n'
    printf 'See [`AGENTS.md`](AGENTS.md) for the agent contract and contribution rules.\n'
  } > README.md
fi

# Make sure the default branch exists with a commit, so the bootstrap script
# (which always branches from origin/$branch or local $branch) has something to
# fork from. We will amend this commit later to fold in the baseline files.
if ! git rev-parse HEAD >/dev/null 2>&1; then
  git add README.md
  git commit -m "chore: initial commit" >/dev/null
fi
# rename the branch to the requested default if necessary (handles --here on a
# repo whose initial branch was created with a different name)
current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [[ -n "$current" && "$current" != "$branch" ]]; then
  git branch -M "$branch" >/dev/null
fi

# ── register in templates/repos.yaml so the bootstrap can find it ─────────
if [[ $register -eq 1 && -f "$REGISTRY" ]]; then
  if command -v yq >/dev/null 2>&1; then
    if yq eval ".repos[] | select(.path == \"$rel_path\") | .path" "$REGISTRY" 2>/dev/null | grep -q .; then
      log "registry" "$rel_path already present, skipping append"
    else
      fp_bool=$( [[ $forgejo_primary -eq 1 ]] && echo true || echo false )
      yq -i ".repos += [{
        \"path\": \"$rel_path\",
        \"slug\": \"${gh_slug:-null}\",
        \"forgejo_slug\": \"${fj_slug:-null}\",
        \"forgejo_primary\": $fp_bool,
        \"default_branch\": \"$branch\",
        \"tier\": \"$tier\",
        \"stack\": \"${stack:-unspecified}\",
        \"deploys_on_merge\": false
      }]" "$REGISTRY"
      # null literal substitution: yq stores 'null' string; convert if we wrote literal "null"
      [[ -z "$gh_slug" ]] && yq -i "(.repos[] | select(.path == \"$rel_path\") | .slug) = null" "$REGISTRY"
      [[ -z "$fj_slug" ]] && yq -i "(.repos[] | select(.path == \"$rel_path\") | .forgejo_slug) = null" "$REGISTRY"
      log "registry" "appended $rel_path to repos.yaml"
    fi
  else
    warn "yq not installed; cannot auto-register $rel_path. Add it manually to $REGISTRY."
    register=0
  fi
fi

# ── apply the agent-readiness baseline ────────────────────────────────────
if [[ -x "$BOOTSTRAP" && $register -eq 1 ]]; then
  log "bootstrap" "applying agent-readiness baseline"
  "$BOOTSTRAP" --apply "$rel_path"
else
  warn "bootstrap script not available or repo not registered; skipping baseline drop"
fi

# Fold the bootstrap's branch into the default branch and squash so the new
# repo's history is one clean initial commit (or two: README + baseline).
if git rev-parse --verify --quiet chore/agent-readiness-baseline >/dev/null; then
  git checkout "$branch" >/dev/null 2>&1
  git merge --ff-only chore/agent-readiness-baseline >/dev/null
  git branch -D chore/agent-readiness-baseline >/dev/null
  # squash the README commit and the baseline commit into one tidy initial commit
  if [[ "$(git rev-list --count HEAD)" == "2" ]]; then
    git reset --soft "$(git rev-list --max-parents=0 HEAD)" >/dev/null
    git commit --amend -m "chore: initial commit with agent-readiness baseline" >/dev/null
  fi
fi
# any straggler files (no-op for fresh repos; useful for --here)
if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git commit -m "chore: agent-readiness baseline" >/dev/null
fi

# ── create remotes + push ─────────────────────────────────────────────────
# Naming convention:
#   forgejo_primary=1 → origin = forgejo, github (if any) = 'github'
#   forgejo_primary=0, forgejo=1 → origin = github, forgejo (if any) = 'forgejo'
#   forgejo=0 → origin = github only (legacy default)
create_forgejo_repo() {
  local owner="$FORGEJO_OWNER" priv
  priv=$( [[ "$visibility" == "private" ]] && echo true || echo false )
  local body
  body=$(jq -nc --arg name "$name" --arg desc "$description" --argjson priv "$priv" --arg branch "$branch" '
    {name: $name, description: $desc, private: $priv, default_branch: $branch, auto_init: false}')
  local code
  code=$(curl -sk -o /tmp/fj-create-$$.json -w '%{http_code}' \
    -H "Authorization: token $FORGEJO_TOKEN" \
    -H "Content-Type: application/json" \
    -X POST "$FORGEJO_URL/api/v1/user/repos" \
    -d "$body")
  if [[ "$code" =~ ^2 || "$code" == "409" ]]; then
    [[ "$code" == "409" ]] && warn "forgejo: $fj_slug already exists; reusing"
    rm -f /tmp/fj-create-$$.json
    return 0
  fi
  err "forgejo create HTTP $code: $(cat /tmp/fj-create-$$.json | head -c 300)"
  rm -f /tmp/fj-create-$$.json
  return 1
}

setup_forgejo_mirror() {
  # Tell Forgejo to push-mirror to GitHub on every commit.
  # Requires FORGEJO_GH_MIRROR_PAT to exist as a Forgejo user setting OR
  # passed explicitly via env.
  local pat="${FORGEJO_GH_MIRROR_PAT:-}"
  [[ -z "$pat" ]] && { warn "FORGEJO_GH_MIRROR_PAT not set; skipping mirror config"; return; }
  local body
  body=$(jq -nc \
    --arg url "https://github.com/$gh_slug.git" \
    --arg user "${MIRROR_GH_USER:-$gh_user}" \
    --arg pw "$pat" '
    {remote_address: $url, remote_username: $user, remote_password: $pw,
     interval: "8h0m0s", sync_on_commit: true}')
  local code
  code=$(curl -sk -o /dev/null -w '%{http_code}' \
    -H "Authorization: token $FORGEJO_TOKEN" \
    -H "Content-Type: application/json" \
    -X POST "$FORGEJO_URL/api/v1/repos/$fj_slug/push_mirrors" \
    -d "$body")
  if [[ "$code" =~ ^2 ]]; then
    log "forgejo" "push mirror → github configured"
  else
    warn "forgejo push-mirror setup HTTP $code (configure manually if needed)"
  fi
}

if [[ $push -eq 1 ]]; then
  # GitHub side
  if [[ $github -eq 1 ]]; then
    if gh repo view "$gh_slug" >/dev/null 2>&1; then
      warn "$gh_slug already exists on github; skipping repo create"
    else
      gh_args=( "$gh_slug" "--$visibility" )
      [[ -n "$description" ]] && gh_args+=( "--description" "$description" )
      gh repo create "${gh_args[@]}" >/dev/null
      log "github" "created https://github.com/$gh_slug"
    fi
  fi

  # Forgejo side
  if [[ $forgejo -eq 1 ]]; then
    create_forgejo_repo || exit 1
    log "forgejo" "created $FORGEJO_URL/$fj_slug"
  fi

  # Wire up local remotes by primacy.
  # Forgejo SSH goes over the Cloudflare TCP tunnel: scp-style git@host for
  # fetch, ssh://git@git-ssh.host for push (the proven-working scheme).
  gh_url="git@github.com:$gh_slug.git"
  fj_fetch_url="git@${FORGEJO_SSH_FETCH_HOST}:$fj_slug.git"
  fj_push_url="ssh://git@${FORGEJO_SSH_PUSH_HOST}/$fj_slug.git"

  add_forgejo_remote() {  # $1 = remote name
    git remote add "$1" "$fj_fetch_url"
    git remote set-url --push "$1" "$fj_push_url"
  }

  git remote remove origin 2>/dev/null || true
  git remote remove forgejo 2>/dev/null || true
  git remote remove github 2>/dev/null || true

  if [[ $forgejo_primary -eq 1 ]]; then
    add_forgejo_remote origin
    [[ $github -eq 1 ]] && git remote add github "$gh_url"
  else
    [[ $github -eq 1 ]] && git remote add origin "$gh_url"
    [[ $forgejo -eq 1 && $github -eq 1 ]] && add_forgejo_remote forgejo
    [[ $forgejo -eq 1 && $github -eq 0 ]] && add_forgejo_remote origin
  fi

  git push -u origin "$branch" >/dev/null
  if [[ $forgejo_primary -eq 0 && $forgejo -eq 1 && $github -eq 1 ]]; then
    git push -u forgejo "$branch" >/dev/null || warn "forgejo push failed"
  fi
  if [[ $forgejo_primary -eq 1 && $github -eq 1 ]]; then
    # Configure server-side push mirror so commits flow Forgejo → GitHub
    setup_forgejo_mirror
  fi

  # commit registry update so the new repo is tracked
  if [[ $register -eq 1 && -d "$TEMPLATES/.git" ]]; then
    if [[ -n "$(git -C "$TEMPLATES" status --porcelain repos.yaml 2>/dev/null)" ]]; then
      git -C "$TEMPLATES" add repos.yaml
      git -C "$TEMPLATES" commit -m "chore(registry): add $rel_path ($slug)" >/dev/null
      git -C "$TEMPLATES" push >/dev/null 2>&1 || warn "templates push failed; commit it later"
      log "registry" "committed registry update"
    fi
  fi

  if [[ $protect -eq 1 && -x "$PROTECT" && $register -eq 1 ]]; then
    log "protect" "applying tier-aware branch protection (--no-checks; tighten later)"
    local_args=( --no-checks )
    if [[ $github -eq 1 && $forgejo -eq 1 ]]; then local_args+=( --both )
    elif [[ $forgejo -eq 1 ]]; then local_args+=( --forgejo )
    fi
    "$PROTECT" "${local_args[@]}" "$rel_path" >/dev/null 2>&1 || \
      warn "branch protection failed (probably free-plan private repo); apply manually later"
  fi

  echo
  [[ -n "$gh_slug" ]] && log "done" "https://github.com/$gh_slug"
  [[ -n "$fj_slug" ]] && log "done" "$FORGEJO_URL/$fj_slug"
else
  echo
  log "done" "$repo_root  (no push requested)"
fi
