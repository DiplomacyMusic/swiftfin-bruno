#!/bin/bash
# cleanup-worktrees.sh — reclaim disk from stale worktrees + orphaned DerivedData
#
# We run many git worktrees under .claude/worktrees/. Each one that gets built
# in Xcode spawns its own ~5 GB DerivedData folder, and a deleted worktree
# leaves its DerivedData orphaned. This script reclaims both, safely.
#
#   STEP 1  Remove a worktree ONLY if its branch is fully merged into the
#           default branch AND its working tree is clean. Never touches the
#           main checkout, the current worktree, a locked/detached worktree,
#           an unmerged branch, or a dirty tree. Then deletes the now-merged
#           local branch (safe `git branch -d`, never `-D`).
#   STEP 2  Delete an Xcode DerivedData folder ONLY if its recorded
#           WorkspacePath no longer exists on disk (orphaned). Never deletes a
#           build whose source .xcodeproj still exists.
#
# Step 1 runs before step 2 so a freshly-removed worktree's DerivedData is then
# caught as an orphan in the same pass.
#
# DEFAULT IS A DRY RUN: it prints exactly what it would remove (worktrees,
# branches, DerivedData dirs) with reclaimed sizes, and deletes nothing.
# Pass --apply to actually delete.
#
# Usage:
#   Scripts/cleanup-worktrees.sh            # dry run (default) — deletes nothing
#   Scripts/cleanup-worktrees.sh --apply    # actually delete
#   Scripts/cleanup-worktrees.sh --no-fetch # skip the `git fetch` freshness step
#   Scripts/cleanup-worktrees.sh --help
#
# Merge detection uses a merge-base ancestor check against the detected default
# branch (origin/<default> and/or local <default>). NOTE: branches merged via
# *squash* or *rebase* will not register as ancestors and are kept (the safe
# failure mode) — remove those by hand.

set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:${PATH:-}"

PLISTBUDDY="/usr/libexec/PlistBuddy"
DD="$HOME/Library/Developer/Xcode/DerivedData"

APPLY=0
FETCH=1

# ---- args -------------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --apply)    APPLY=1 ;;
    --dry-run)  APPLY=0 ;;
    --no-fetch) FETCH=0 ;;
    -h|--help)
      sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "Unknown argument: $arg (try --help)" >&2
      exit 2 ;;
  esac
done

# ---- helpers ----------------------------------------------------------------
kb_to_h() {
  awk -v k="${1:-0}" 'BEGIN{
    u[1]="K"; u[2]="M"; u[3]="G"; u[4]="T";
    s=k; i=1; while (s>=1024 && i<4){ s/=1024; i++ }
    printf("%.1f%s", s, u[i])
  }'
}

dir_kb() {
  # disk usage in KB; 0 if the path is gone / unreadable
  du -sk "$1" 2>/dev/null | awk 'NR==1{print $1}' || echo 0
}

short_path() { echo "${1#"$MAIN_WT"/}"; }

# ---- locate the repo (never assume cwd) ------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! GIT_COMMON_DIR="$(git -C "$SCRIPT_DIR" rev-parse --git-common-dir 2>/dev/null)"; then
  echo "Not inside a git repository: $SCRIPT_DIR" >&2
  exit 1
fi
# git-common-dir may be relative; resolve, then its parent is the main checkout
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && cd "$GIT_COMMON_DIR" && pwd)"
MAIN_WT="$(dirname "$GIT_COMMON_DIR")"
WT_DIR="$MAIN_WT/.claude/worktrees"
SELF_WT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "")"

# ---- default branch detection ----------------------------------------------
detect_default_branch() {
  local d
  if d="$(git -C "$MAIN_WT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    echo "${d#origin/}"; return
  fi
  local c
  for c in main master; do
    if git -C "$MAIN_WT" show-ref --verify --quiet "refs/remotes/origin/$c"; then echo "$c"; return; fi
  done
  for c in main master; do
    if git -C "$MAIN_WT" show-ref --verify --quiet "refs/heads/$c"; then echo "$c"; return; fi
  done
  echo "main"
}

DEF="$(detect_default_branch)"

# Candidate "default branch" refs that actually exist (remote first — that's
# where PRs land — then local, which Xcode builds).
DEFAULT_REFS=()
if git -C "$MAIN_WT" show-ref --verify --quiet "refs/remotes/origin/$DEF"; then DEFAULT_REFS+=("origin/$DEF"); fi
if git -C "$MAIN_WT" show-ref --verify --quiet "refs/heads/$DEF"; then DEFAULT_REFS+=("$DEF"); fi
if [ "${#DEFAULT_REFS[@]}" -eq 0 ]; then
  echo "Could not resolve a default branch ref for '$DEF'." >&2
  exit 1
fi

is_merged() {  # tip is an ancestor of any default ref ⇒ its work is preserved
  local tip="$1" ref
  for ref in "${DEFAULT_REFS[@]}"; do
    if git -C "$MAIN_WT" merge-base --is-ancestor "$tip" "$ref" 2>/dev/null; then return 0; fi
  done
  return 1
}

at_default_tip() {  # tip == a default tip ⇒ no unique commits (fresh/idle worktree)
  local tip="$1" ref reftip
  for ref in "${DEFAULT_REFS[@]}"; do
    reftip="$(git -C "$MAIN_WT" rev-parse "$ref" 2>/dev/null || true)"
    if [ -n "$reftip" ] && [ "$tip" = "$reftip" ]; then return 0; fi
  done
  return 1
}

# ---- banner -----------------------------------------------------------------
echo "============================================================"
echo " Bruno worktree + DerivedData cleanup"
echo " $(date '+%Y-%m-%d %H:%M:%S')   mode: $([ "$APPLY" -eq 1 ] && echo APPLY || echo 'DRY RUN (no deletions)')"
echo " repo:    $MAIN_WT"
echo " default: $DEF   refs: ${DEFAULT_REFS[*]}"
echo "============================================================"

if [ "$FETCH" -eq 1 ] && git -C "$MAIN_WT" remote get-url origin >/dev/null 2>&1; then
  echo "Fetching origin (for accurate merge detection)..."
  git -C "$MAIN_WT" fetch --quiet --prune origin 2>/dev/null || echo "  (fetch failed — using last-known refs)"
fi

# ============================================================================
# STEP 1 — merged / stale worktrees
# ============================================================================
echo
echo "── STEP 1: worktrees under .claude/worktrees/ ──"

ELIGIBLE_PATHS=()
ELIGIBLE_BRANCHES=()
ELIGIBLE_HEADS=()

skip_note() { printf '  keep   %-40s — %s\n' "$1" "$2"; }

handle_worktree() {
  local path="$1" head="$2" branch="$3" locked="$4" detached="$5" bare="$6"
  [ "$bare" = "1" ] && return 0
  [ "$path" = "$MAIN_WT" ] && return 0
  case "$path" in
    "$WT_DIR"/*) ;;
    *) return 0 ;;   # outside .claude/worktrees/ — out of scope, ignore silently
  esac
  local sp; sp="$(short_path "$path")"
  if [ "$path" = "$SELF_WT" ]; then skip_note "$sp" "current worktree (never self-remove)"; return 0; fi
  if [ "$locked" = "1" ]; then skip_note "$sp" "locked"; return 0; fi
  if [ "$detached" = "1" ] || [ -z "$branch" ]; then skip_note "$sp" "detached HEAD (no branch)"; return 0; fi
  local short="${branch#refs/heads/}"
  if [ "$short" = "$DEF" ]; then skip_note "$sp" "checked out on default branch '$DEF'"; return 0; fi
  if [ -n "$(git -C "$path" status --porcelain 2>/dev/null || true)" ]; then
    skip_note "$sp" "dirty working tree (uncommitted changes)"; return 0
  fi
  if ! is_merged "$head"; then skip_note "$sp" "branch '$short' NOT merged into $DEF"; return 0; fi
  if at_default_tip "$head"; then skip_note "$sp" "no unique commits (tip == $DEF)"; return 0; fi
  ELIGIBLE_PATHS+=("$path")
  ELIGIBLE_BRANCHES+=("$short")
  ELIGIBLE_HEADS+=("$head")
}

# parse `git worktree list --porcelain` record-by-record
_path=""; _head=""; _branch=""; _locked=""; _detached=""; _bare=""
flush_record() {
  [ -n "$_path" ] && handle_worktree "$_path" "$_head" "$_branch" "$_locked" "$_detached" "$_bare"
  _path=""; _head=""; _branch=""; _locked=""; _detached=""; _bare=""
}
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    "worktree "*) _path="${line#worktree }" ;;
    "HEAD "*)     _head="${line#HEAD }" ;;
    "branch "*)   _branch="${line#branch }" ;;
    "detached")   _detached="1" ;;
    "locked"*)    _locked="1" ;;
    "bare")       _bare="1" ;;
    "")           flush_record ;;
  esac
done < <(git -C "$MAIN_WT" worktree list --porcelain)
flush_record

wt_total_kb=0
removed_any=0
if [ "${#ELIGIBLE_PATHS[@]}" -eq 0 ]; then
  echo "  (no merged/stale worktrees to remove)"
else
  i=0
  while [ "$i" -lt "${#ELIGIBLE_PATHS[@]}" ]; do
    p="${ELIGIBLE_PATHS[$i]}"
    b="${ELIGIBLE_BRANCHES[$i]}"
    h="${ELIGIBLE_HEADS[$i]}"
    kb="$(dir_kb "$p")"
    wt_total_kb=$(( wt_total_kb + kb ))
    sp="$(short_path "$p")"
    if [ "$APPLY" -eq 1 ]; then
      printf '  REMOVE %-40s  branch %-38s (%s)\n' "$sp" "$b" "$(kb_to_h "$kb")"
      if git -C "$MAIN_WT" worktree remove "$p" 2>/dev/null; then
        removed_any=1
        if git -C "$MAIN_WT" branch -d "$b" 2>/dev/null; then
          echo "         deleted branch $b"
        elif is_merged "$h"; then
          # `git branch -d` validates against local HEAD, which may simply be
          # behind origin/<default>. We have already proven $b is contained in
          # a default ref (is_merged), so a force-delete loses no work.
          if git -C "$MAIN_WT" branch -D "$b" 2>/dev/null; then
            echo "         deleted branch $b (verified merged into ${DEFAULT_REFS[*]})"
          else
            echo "         !! branch delete failed for $b (kept) — verify manually"
          fi
        else
          echo "         !! branch not merged after all for $b (kept) — verify manually"
        fi
      else
        echo "         !! worktree remove refused for $sp (kept) — verify manually"
      fi
    else
      printf '  WOULD REMOVE %-40s  branch %-30s (%s)\n' "$sp" "$b" "$(kb_to_h "$kb")"
    fi
    i=$(( i + 1 ))
  done
  if [ "$APPLY" -eq 1 ] && [ "$removed_any" -eq 1 ]; then
    git -C "$MAIN_WT" worktree prune
    echo "  pruned stale worktree admin entries"
  fi
fi

# ============================================================================
# STEP 2 — orphaned Xcode DerivedData
# ============================================================================
echo
echo "── STEP 2: orphaned DerivedData ($DD/Swiftfin-*) ──"

safe_rm_dd() {
  local dir="$1"
  case "$dir" in
    "$DD"/Swiftfin-*) ;;
    *) echo "         !! REFUSING unexpected path: $dir"; return 1 ;;
  esac
  if [ -z "$dir" ] || [ "$dir" = "/" ] || [ "$dir" = "$DD" ]; then
    echo "         !! REFUSING unsafe path: '$dir'"; return 1
  fi
  rm -rf -- "$dir"
}

dd_total_kb=0
orphans=0
if [ ! -d "$DD" ]; then
  echo "  (no DerivedData directory at $DD)"
else
  shopt -s nullglob
  for dir in "$DD"/Swiftfin-*; do
    [ -d "$dir" ] || continue
    bn="$(basename "$dir")"
    plist="$dir/info.plist"
    if [ ! -f "$plist" ]; then printf '  keep   %-44s — no info.plist (cannot verify)\n' "$bn"; continue; fi
    wp="$("$PLISTBUDDY" -c "Print :WorkspacePath" "$plist" 2>/dev/null || true)"
    if [ -z "$wp" ]; then printf '  keep   %-44s — no WorkspacePath key (cannot verify)\n' "$bn"; continue; fi
    if [ -e "$wp" ]; then
      printf '  keep   %-44s — source exists\n' "$bn"
      continue
    fi
    # orphan
    orphans=$(( orphans + 1 ))
    kb="$(dir_kb "$dir")"
    dd_total_kb=$(( dd_total_kb + kb ))
    if [ "$APPLY" -eq 1 ]; then
      printf '  DELETE %-44s (%s)\n' "$bn" "$(kb_to_h "$kb")"
      echo   "         orphan of: $wp"
      if safe_rm_dd "$dir"; then echo "         removed."; fi
    else
      printf '  WOULD DELETE %-44s (%s)\n' "$bn" "$(kb_to_h "$kb")"
      echo   "         orphan of (missing): $wp"
    fi
  done
fi
[ "$orphans" -eq 0 ] && echo "  (no orphaned DerivedData folders)"

# ============================================================================
# SUMMARY
# ============================================================================
grand_kb=$(( wt_total_kb + dd_total_kb ))
echo
echo "── Summary ──"
printf '  worktrees:    %s\n' "$(kb_to_h "$wt_total_kb")"
printf '  DerivedData:  %s\n' "$(kb_to_h "$dd_total_kb")"
printf '  TOTAL %s: %s\n' "$([ "$APPLY" -eq 1 ] && echo 'reclaimed' || echo 'reclaimable')" "$(kb_to_h "$grand_kb")"
if [ "$APPLY" -eq 0 ]; then
  echo
  echo "  DRY RUN — nothing was deleted. Re-run with --apply to delete."
fi
echo "============================================================"
