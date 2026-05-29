#!/bin/bash

# Complete Idempotent Git Homelab Sync Script
# Handles: Missing repo detection, cloning, syncing, conflict resolution
# For: Personal repos + owned organizations only
# Structure: Category-based organization:
# ~/git/l3ocifer/repo-name (personal)
# ~/git/websites/website-repos (websites)  
# ~/git/ai/ai-repos (AI projects)
# ~/git/games/game-repos (games)
# ~/git/org-name/repo-name (organization repositories)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration - Organizations you own/control (admin role only)
OWNED_ORGS=(
    "AuthorWorks"
    "crypto-dale"
    "GitHired-co"
    "omnilemma"
    "pieroot42"
    "potluck-pub"
    "provisionsgroup"
    "the-blink"
    "ursulai"
)

# Configuration
DRY_RUN=false
VERBOSE=false
AUTO_CLONE=false
MAX_PARALLEL_CLONES=5
LOG_FILE="$HOME/git/.homelab-sync-$(date +%Y%m%d_%H%M%S).log"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --auto-clone) AUTO_CLONE=true; shift ;;
        --parallel=*) MAX_PARALLEL_CLONES="${1#*=}"; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Complete idempotent git sync for homelab environments."
            echo "Creates optimal directory structure and keeps everything in sync."
            echo ""
            echo "Options:"
            echo "  --dry-run       Show what would be done without making changes"
            echo "  --verbose       Show detailed output"
            echo "  --auto-clone    Automatically clone missing repos (no prompts)"
            echo "  --parallel=N    Clone N repos in parallel (default: 5)"
            echo "  --help          Show this help message"
            echo ""
            echo "Directory Structure:"
            echo "  ~/git/l3ocifer/repo-name     (personal repositories)"
            echo "  ~/git/websites/repo-name     (website repositories)"
            echo "  ~/git/ai/repo-name           (AI/ML repositories)"
            echo "  ~/git/games/repo-name        (game repositories)"
            echo "  ~/git/org-name/repo-name     (organization repositories)"
            echo ""
            echo "Owned Organizations:"
            if [ ${#OWNED_ORGS[@]} -eq 0 ]; then
                echo "  (none configured - edit script to add organizations)"
            else
                printf "  - %s\n" "${OWNED_ORGS[@]}"
            fi
            exit 0
            ;;
        *) echo "Unknown option: $1. Use --help for usage."; exit 1 ;;
    esac
done

# Logging
log() { echo -e "$1" | tee -a "$LOG_FILE"; }
mkdir -p "$(dirname "$LOG_FILE")"

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}" | tee "$LOG_FILE"
echo -e "${BLUE}                    Homelab Git Sync                            ${NC}" | tee -a "$LOG_FILE"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
[ "$DRY_RUN" = true ] && log "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
log ""

# Check prerequisites
if ! command -v gh &> /dev/null; then
    log "${RED}Error: GitHub CLI (gh) not found. Please install it.${NC}"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    log "${RED}Error: GitHub CLI not authenticated. Run: gh auth login${NC}"
    exit 1
fi

GITHUB_USER=$(gh api user --jq .login)
log "${CYAN}GitHub User: $GITHUB_USER${NC}"
if [ ${#OWNED_ORGS[@]} -gt 0 ]; then
    log "${CYAN}Owned Organizations: ${OWNED_ORGS[*]}${NC}"
else
    log "${CYAN}Owned Organizations: (none configured)${NC}"
fi

# Create temp files
REMOTE_REPOS=$(mktemp)
LOCAL_REPOS=$(mktemp)
MISSING_REPOS=$(mktemp)
cleanup() { rm -f "$REMOTE_REPOS" "$LOCAL_REPOS" "$MISSING_REPOS"; }
trap cleanup EXIT

# Function: Get remote repositories
get_remote_repos() {
    log "${BLUE}=== Fetching Remote Repositories ===${NC}"
    
    # Personal repos (non-archived, owned by user)
    log "${YELLOW}Fetching personal repositories...${NC}"
    gh api "user/repos?per_page=100&affiliation=owner" --paginate \
        --jq '.[] | select(.owner.login == "'"$GITHUB_USER"'" and .archived == false and .fork == false) | .full_name' \
        >> "$REMOTE_REPOS" 2>/dev/null
    
    # Owned organization repos
    for org in "${OWNED_ORGS[@]}"; do
        log "${YELLOW}Fetching $org repositories...${NC}"
        gh api "orgs/$org/repos?per_page=100" --paginate \
            --jq '.[] | select(.archived == false) | .full_name' \
            >> "$REMOTE_REPOS" 2>/dev/null || {
            log "${YELLOW}  Warning: Could not access $org (may not exist or no permission)${NC}"
        }
    done
    
    sort -u "$REMOTE_REPOS" -o "$REMOTE_REPOS"
    local total=$(wc -l < "$REMOTE_REPOS" | tr -d ' ')
    log "${GREEN}Found $total remote repositories${NC}"
}

# Function: Scan local repositories
scan_local_repos() {
    log "${BLUE}=== Scanning Local Repositories ===${NC}"
    
    # Find all git repos up to 3 levels deep (personal + org/repo structure)
    find ~/git -maxdepth 3 -name ".git" -type d 2>/dev/null | while read -r gitdir; do
        repo_dir=$(dirname "$gitdir")
        cd "$repo_dir" 2>/dev/null || continue
        
        # Check for GitHub remotes
        for remote in origin upstream; do
            remote_url=$(git remote get-url "$remote" 2>/dev/null)
            if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/]+?)(\.git)?$ ]]; then
                owner="${BASH_REMATCH[1]}"
                repo="${BASH_REMATCH[2]%.git}"
                echo "${owner}/${repo}" >> "$LOCAL_REPOS"
                break
            fi
        done
    done
    
    sort -u "$LOCAL_REPOS" -o "$LOCAL_REPOS"
    local total=$(wc -l < "$LOCAL_REPOS" | tr -d ' ')
    log "${GREEN}Found $total local repositories${NC}"
}

# Function: Clone missing repositories
clone_missing_repos() {
    comm -23 "$REMOTE_REPOS" "$LOCAL_REPOS" > "$MISSING_REPOS"
    local missing_count=$(wc -l < "$MISSING_REPOS" | tr -d ' ')
    
    if [ "$missing_count" -eq 0 ]; then
        log "${GREEN}All repositories are already cloned locally!${NC}"
        return 0
    fi
    
    log ""
    log "${YELLOW}=== Missing Repositories ===${NC}"
    log "${YELLOW}Found $missing_count missing repositories:${NC}"
    
    while IFS= read -r repo; do
        log "  ${RED}✗${NC} $repo"
    done < "$MISSING_REPOS"
    
    # Determine if we should clone
    local should_clone=false
    if [ "$AUTO_CLONE" = true ]; then
        should_clone=true
        log ""
        log "${CYAN}Auto-cloning enabled...${NC}"
    elif [ "$DRY_RUN" = true ]; then
        log ""
        log "${CYAN}Would clone these repositories (dry run)${NC}"
        return 0
    else
        log ""
        log "${CYAN}Clone missing repositories? (y/n/s for select)${NC}"
        read -r response
        case "$response" in
            [Yy]*) should_clone=true ;;
            [Ss]*) 
                log "${CYAN}Select repositories to clone:${NC}"
                SELECTED_REPOS=$(mktemp)
                while IFS= read -r repo; do
                    log -n "Clone ${YELLOW}$repo${NC}? (y/n) "
                    read -r choice
                    [[ "$choice" =~ ^[Yy]$ ]] && echo "$repo" >> "$SELECTED_REPOS"
                done < "$MISSING_REPOS"
                cp "$SELECTED_REPOS" "$MISSING_REPOS"
                rm -f "$SELECTED_REPOS"
                should_clone=true
                ;;
            *) log "${YELLOW}Skipping clone operation${NC}"; return 0 ;;
        esac
    fi
    
    if [ "$should_clone" = true ]; then
        log ""
        log "${BLUE}=== Cloning Repositories ===${NC}"
        
        # Function to clone a single repo
        clone_repo() {
            local repo=$1
            local owner=$(echo "$repo" | cut -d'/' -f1)
            local repo_name=$(echo "$repo" | cut -d'/' -f2)
            
            # Determine target directory based on optimal structure
            if [ "$owner" = "$GITHUB_USER" ]; then
                # Personal repo: ~/git/repo-name
                target_dir="$HOME/git/$repo_name"
            else
                # Organization repo: ~/git/org-name/repo-name
                target_dir="$HOME/git/$owner/$repo_name"
                mkdir -p "$HOME/git/$owner"
            fi
            
            if [ -d "$target_dir" ]; then
                log "${YELLOW}Exists: $repo${NC}"
                return 0
            fi
            
            log "Cloning: $repo → $target_dir"
            
            if [ "$DRY_RUN" = false ]; then
                if gh repo clone "$repo" "$target_dir" -- --recurse-submodules --single-branch; then
                    log "${GREEN}✓ $repo${NC}"
                    
                    # Set up additional configuration
                    cd "$target_dir"
                    
                    # Add upstream for forks
                    if [ "$(gh api "repos/$repo" --jq '.fork // false')" = "true" ]; then
                        upstream=$(gh api "repos/$repo" --jq '.parent.full_name // empty')
                        if [ -n "$upstream" ]; then
                            git remote add upstream "git@github.com:${upstream}.git" 2>/dev/null
                            log "  → Added upstream: $upstream"
                        fi
                    fi
                    
                    # Initialize Git LFS if needed
                    if [ -f ".gitattributes" ] && grep -q "filter=lfs" ".gitattributes"; then
                        git lfs install --local >/dev/null 2>&1
                        git lfs pull >/dev/null 2>&1
                        log "  → Initialized Git LFS"
                    fi
                    
                    return 0
                else
                    log "${RED}✗ Failed: $repo${NC}"
                    return 1
                fi
            else
                log "${CYAN}Would clone: $repo${NC}"
                return 0
            fi
        }
        
        # Export function for parallel execution
        export -f clone_repo log
        export GITHUB_USER DRY_RUN GREEN RED YELLOW CYAN NC HOME
        
        # Clone in parallel
        cat "$MISSING_REPOS" | xargs -P "$MAX_PARALLEL_CLONES" -I {} bash -c 'clone_repo "$@"' _ {}
        
        log "${GREEN}Clone operation complete!${NC}"
    fi
}

# Function: Sync existing repositories
sync_repos() {
    log ""
    log "${BLUE}=== Syncing Existing Repositories ===${NC}"
    
    # Statistics
    local total_repos=0
    local updated_repos=0
    local repos_with_changes=()
    local repos_with_errors=()
    local repos_no_remote=()
    local repos_need_intervention=()
    local repos_auto_resolved=()
    
    # SSH key check
    if ! ssh-add -l &>/dev/null; then
        log "${YELLOW}Loading SSH key...${NC}"
        for key in ~/.ssh/id_rsa ~/.ssh/id_ed25519 ~/.ssh/leo-github; do
            if [ -f "$key" ]; then
                ssh-add "$key" 2>/dev/null && log "${GREEN}SSH key loaded${NC}" && break
            fi
        done
    fi
    
    # Helper functions
    stash_if_needed() {
        if [ -n "$(git status --porcelain)" ]; then
            [ "$VERBOSE" = true ] && log "  → Stashing local changes..."
            if [ "$DRY_RUN" = false ]; then
                git stash push -m "Auto-stash before sync $(date +%Y%m%d_%H%M%S)" --include-untracked >/dev/null 2>&1
            fi
            return 0
        fi
        return 1
    }
    
    attempt_auto_merge() {
        local repo_name=$1
        local current_branch=$2
        
        local conflicted_files=$(git diff --name-only --diff-filter=U)
        [ -z "$conflicted_files" ] && return 0
        
        log "${YELLOW}  ⚠ Merge conflicts detected. Attempting auto-resolution...${NC}"
        
        # Strategy 1: Auto-resolve generated files
        local generated_patterns=("package-lock.json" "yarn.lock" "Cargo.lock" "go.sum" "poetry.lock" "Gemfile.lock")
        local all_generated=true
        
        for file in $conflicted_files; do
            local is_generated=false
            for pattern in "${generated_patterns[@]}"; do
                if [[ "$file" == "$pattern" ]]; then
                    is_generated=true
                    break
                fi
            done
            if [ "$is_generated" = false ]; then
                all_generated=false
                break
            fi
        done
        
        if [ "$all_generated" = true ]; then
            log "  → Auto-resolving generated file conflicts..."
            if [ "$DRY_RUN" = false ]; then
                for file in $conflicted_files; do
                    git checkout --theirs "$file" && git add "$file"
                done
                git commit -m "Auto-merge: Accept remote version of generated files"
            fi
            repos_auto_resolved+=("$repo_name (generated files)")
            return 0
        fi
        
        # Strategy 2: Try rebase
        if [ "$DRY_RUN" = false ]; then
            git rebase --abort 2>/dev/null
            if git rebase "origin/$current_branch" 2>/dev/null; then
                log "${GREEN}  ✓ Successfully rebased${NC}"
                repos_auto_resolved+=("$repo_name (rebased)")
                return 0
            fi
            git rebase --abort 2>/dev/null
        fi
        
        return 1
    }
    
    process_repo() {
        local repo_dir=$1
        local repo_name=$2
        
        cd "$repo_dir" || return 1
        total_repos=$((total_repos + 1))
        
        # Check for remote
        if ! git remote -v | grep -q "origin"; then
            repos_no_remote+=("$repo_name")
            return 0
        fi
        
        # Track local changes
        local had_changes=false
        local stashed=false
        [ -n "$(git status --porcelain)" ] && had_changes=true
        
        [ "$VERBOSE" = true ] && log "${YELLOW}Syncing: $repo_name${NC}"
        
        # Fetch updates
        if [ "$DRY_RUN" = false ]; then
            if ! git fetch origin --prune >/dev/null 2>&1; then
                repos_with_errors+=("$repo_name (fetch failed)")
                return 1
            fi
        fi
        
        # Get branch info
        local current_branch=$(git branch --show-current)
        if [ -z "$current_branch" ]; then
            repos_with_errors+=("$repo_name (detached HEAD)")
            return 1
        fi
        
        # Check if we have upstream
        local remote_ref
        if ! remote_ref=$(git rev-parse "@{u}" 2>/dev/null); then
            # Try to set upstream
            if [ "$DRY_RUN" = false ] && git ls-remote --heads origin "$current_branch" | grep -q "$current_branch"; then
                git branch --set-upstream-to="origin/$current_branch" "$current_branch" >/dev/null 2>&1
                remote_ref=$(git rev-parse "@{u}" 2>/dev/null)
            fi
            
            if [ -z "$remote_ref" ]; then
                [ "$had_changes" = true ] && repos_with_changes+=("$repo_name (no upstream)")
                return 0
            fi
        fi
        
        # Compare with remote
        local local_ref=$(git rev-parse "@" 2>/dev/null)
        local base_ref=$(git merge-base "@" "@{u}" 2>/dev/null)
        
        if [ "$local_ref" = "$remote_ref" ]; then
            [ "$VERBOSE" = true ] && log "${GREEN}  ✓ Up to date${NC}"
            [ "$had_changes" = true ] && repos_with_changes+=("$repo_name (local changes)")
        elif [ "$local_ref" = "$base_ref" ]; then
            # We're behind - can fast-forward
            [ "$VERBOSE" = true ] && log "${BLUE}  ↓ Pulling updates...${NC}"
            
            if [ "$DRY_RUN" = false ]; then
                # Stash if needed
                stash_if_needed && stashed=true
                
                if git pull origin "$current_branch" --ff-only >/dev/null 2>&1; then
                    [ "$VERBOSE" = true ] && log "${GREEN}  ✓ Updated${NC}"
                    updated_repos=$((updated_repos + 1))
                    
                    # Restore stash
                    [ "$stashed" = true ] && git stash pop >/dev/null 2>&1
                    
                    # Update submodules if present
                    [ -f ".gitmodules" ] && git submodule update --init --recursive >/dev/null 2>&1
                else
                    # Fast-forward failed, try merge with auto-resolution
                    if attempt_auto_merge "$repo_name" "$current_branch"; then
                        [ "$VERBOSE" = true ] && log "${GREEN}  ✓ Auto-resolved and updated${NC}"
                        updated_repos=$((updated_repos + 1))
                        [ "$stashed" = true ] && git stash pop >/dev/null 2>&1
                    else
                        [ "$VERBOSE" = true ] && log "${RED}  ✗ Needs manual intervention${NC}"
                        repos_need_intervention+=("$repo_name (merge conflicts)")
                        [ "$stashed" = true ] && git stash pop >/dev/null 2>&1
                    fi
                fi
            else
                [ "$VERBOSE" = true ] && log "${CYAN}  → Would update (dry run)${NC}"
            fi
        elif [ "$remote_ref" = "$base_ref" ]; then
            # We're ahead
            [ "$VERBOSE" = true ] && log "${YELLOW}  ↑ Ahead of remote${NC}"
            repos_with_changes+=("$repo_name (ahead)")
        else
            # Diverged
            [ "$VERBOSE" = true ] && log "${YELLOW}  ↕ Diverged from remote${NC}"
            repos_with_changes+=("$repo_name (diverged)")
        fi
        
        return 0
    }
    
    # Process all repositories
    # Personal repos in ~/git/
    for repo_dir in ~/git/*/; do
        [ ! -d "$repo_dir/.git" ] && continue
        local repo_name=$(basename "$repo_dir")
        process_repo "$repo_dir" "$repo_name"
    done
    
    # Organization repos in ~/git/org/
    for org_dir in ~/git/*/; do
        [ ! -d "$org_dir" ] && continue
        [ -d "$org_dir/.git" ] && continue  # Skip if it's actually a repo
        
        local org_name=$(basename "$org_dir")
        for repo_dir in "$org_dir"*/; do
            [ ! -d "$repo_dir/.git" ] && continue
            local repo_name="$org_name/$(basename "$repo_dir")"
            process_repo "$repo_dir" "$repo_name"
        done
    done
    
    # Summary
    log ""
    log "${BLUE}=== Sync Summary ===${NC}"
    log "Total repositories: $total_repos"
    log "Updated repositories: $updated_repos"
    
    if [ ${#repos_auto_resolved[@]} -gt 0 ]; then
        log ""
        log "${GREEN}Auto-resolved conflicts:${NC}"
        printf '  - %s\n' "${repos_auto_resolved[@]}" | tee -a "$LOG_FILE"
    fi
    
    if [ ${#repos_with_changes[@]} -gt 0 ]; then
        log ""
        log "${YELLOW}Repositories with local changes/ahead:${NC}"
        printf '  - %s\n' "${repos_with_changes[@]}" | tee -a "$LOG_FILE"
    fi
    
    if [ ${#repos_no_remote[@]} -gt 0 ]; then
        log ""
        log "${YELLOW}Repositories without remote:${NC}"
        printf '  - %s\n' "${repos_no_remote[@]}" | tee -a "$LOG_FILE"
    fi
    
    if [ ${#repos_with_errors[@]} -gt 0 ]; then
        log ""
        log "${RED}Repositories with errors:${NC}"
        printf '  - %s\n' "${repos_with_errors[@]}" | tee -a "$LOG_FILE"
    fi
    
    if [ ${#repos_need_intervention[@]} -gt 0 ]; then
        log ""
        log "${MAGENTA}=== MANUAL INTERVENTION REQUIRED ===${NC}"
        log "${MAGENTA}The following repositories need manual attention:${NC}"
        printf '  - %s\n' "${repos_need_intervention[@]}" | tee -a "$LOG_FILE"
        log ""
        log "${YELLOW}To resolve manually:${NC}"
        log "  1. cd ~/git/<repo-path>"
        log "  2. git status"
        log "  3. Resolve conflicts or reset: git reset --hard origin/<branch>"
        return 1
    fi
    
    return 0
}

# Main execution
main() {
    get_remote_repos
    scan_local_repos
    clone_missing_repos
    
    local sync_success=true
    if ! sync_repos; then
        sync_success=false
    fi
    
    # Final summary
    log ""
    log "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    log "${BLUE}                         Final Summary                           ${NC}"
    log "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    
    local remote_count=$(wc -l < "$REMOTE_REPOS" | tr -d ' ')
    local local_count=$(wc -l < "$LOCAL_REPOS" | tr -d ' ')
    local missing_count=$(wc -l < "$MISSING_REPOS" | tr -d ' ')
    
    log "Remote repositories (owned): $remote_count"
    log "Local repositories: $local_count"
    log "Missing repositories: $missing_count"
    
    if [ "$sync_success" = true ]; then
        log "${GREEN}✓ All repositories are synchronized${NC}"
    else
        log "${YELLOW}⚠ Some repositories need manual attention${NC}"
    fi
    
    log ""
    log "${CYAN}Directory Structure:${NC}"
    log "  ~/git/repo-name              (personal repositories)"
    log "  ~/git/org-name/repo-name     (organization repositories)"
    log ""
    log "${CYAN}For homelab syncthing:${NC}"
    log "  1. Add ~/git to syncthing on all machines"
    log "  2. Run this script on each machine after sync"
    log "  3. Consider adding to cron/login scripts"
    log ""
    log "${GREEN}Homelab Git Sync Complete!${NC}"
    log "${CYAN}Log saved to: $LOG_FILE${NC}"
    
    # Exit with appropriate code
    [ "$sync_success" = false ] && exit 1 || exit 0
}

# Run main function
main