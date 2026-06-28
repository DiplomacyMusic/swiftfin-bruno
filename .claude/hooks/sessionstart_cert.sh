#!/usr/bin/env bash
# SessionStart cert injector for Bruno.
#
# Fires when a Claude Code session starts in this repo. Reads the hook
# input JSON from stdin, extracts session_id, and emits additionalContext
# containing:
#   - the canonical cert ritual (.claude/CERTIFICATION.md)
#   - the exact receipt path the agent must write
#   - a live prelude: last 20 git commits, current gate mode, the verified
#     toolchain, and the auto-detected worktree/build facts
#
# The hook never blocks and exits 0 always. Its job is to plant the cert
# challenge LATE in context, where recency favors it over the buried
# CLAUDE.md cold-start section.
#
# The hook does NOT run a build. The agent runs the toolchain probe itself,
# in front of Daniel, as proof of grounding (receipt section 5).

set -u

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"

# Defensive: if we can't even figure out the project root, exit silently.
[ -d "$project_dir/.claude" ] || exit 0

cert_doc_path="$project_dir/.claude/CERTIFICATION.md"
mode_path="$project_dir/.claude/.cert/mode"

# Read the canonical cert ritual if present (it should be — same commit).
if [ -f "$cert_doc_path" ]; then
    cert_doc="$(cat "$cert_doc_path")"
else
    cert_doc="(CERTIFICATION.md missing — install the cert assets per the cert PR)"
fi

# Resolve current gate mode (default warn if file missing/unreadable).
if [ -f "$mode_path" ]; then
    gate_mode="$(tr -d '[:space:]' < "$mode_path")"
else
    gate_mode="warn"
fi
[ -z "$gate_mode" ] && gate_mode="warn"

# Live prelude: last 20 commits.
git_log="$(git -C "$project_dir" log --oneline -20 2>/dev/null || echo '(git log unavailable)')"

# Worktree detection. Compares git-dir vs git-common-dir; if they
# differ, we're in a worktree, not the main checkout.
worktree_status="no"
worktree_branch=""
worktree_path=""
main_repo_path=""
git_dir="$(git -C "$project_dir" rev-parse --git-dir 2>/dev/null)"
common_dir="$(git -C "$project_dir" rev-parse --git-common-dir 2>/dev/null)"
if [ -n "$git_dir" ] && [ -n "$common_dir" ] && [ "$git_dir" != "$common_dir" ]; then
    worktree_status="yes"
    worktree_path="$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null)"
    worktree_branch="$(git -C "$project_dir" branch --show-current 2>/dev/null)"
    if [ -d "$common_dir" ]; then
        main_repo_path="$(cd "$(dirname "$common_dir")" 2>/dev/null && pwd)"
    fi
fi

# Compose the execution-environment block.
if [ "$worktree_status" = "yes" ]; then
    worktree_block="EXECUTION ENVIRONMENT — auto-detected facts:

  Worktree:      yes
  Worktree path: ${worktree_path}
  Branch:        ${worktree_branch}
  Main repo:     ${main_repo_path}

  ----------------------------------------------------------------
  The owner builds 'main' in Xcode (worktree -> PR -> owner merges).
  Code in THIS worktree is NOT what his Xcode builds until it lands on
  'main'. So any 'ask Daniel to verify' command must be a headless
  xcodebuild scoped to the worktree path, OR you must say the change
  has to merge to 'main' first. Do not hand him a command that builds
  the wrong tree.
  ----------------------------------------------------------------

  Headless compile gate scoped to THIS worktree (verifies compilation
  only — CODE_SIGNING_ALLOWED=NO; a runnable sim build needs ad-hoc
  signing, see BRUNO_NOTES.md §Toolchain):

    cd \"${worktree_path}\" && xcodebuild -project Swiftfin.xcodeproj \\
      -scheme \"Swiftfin tvOS\" \\
      -destination 'generic/platform=tvOS Simulator' \\
      -skipMacroValidation build CODE_SIGNING_ALLOWED=NO

  Section 10 of your cert receipt MUST include one of these concrete
  tokens (the gate enforces it in worktrees): 'xcodebuild', the scheme
  'Swiftfin tvOS', a 'cd <worktree>' invocation, OR an explicit no-build
  phrase ('docs-only', 'no build', 'pure markdown', 'no Xcode')."
else
    worktree_block="EXECUTION ENVIRONMENT — auto-detected facts:

  Worktree:    no (operating on main checkout)
  Project dir: ${project_dir}

  Standard path applies — the owner builds 'main' in Xcode. Verify
  compilation headlessly with the compile gate (BRUNO_NOTES.md §Toolchain):

    xcodebuild -project Swiftfin.xcodeproj -scheme \"Swiftfin tvOS\" \\
      -destination 'generic/platform=tvOS Simulator' \\
      -skipMacroValidation build CODE_SIGNING_ALLOWED=NO"
fi

# Compute the receipt path the agent must write.
if [ -n "$session_id" ]; then
    receipt_path=".claude/.cert/${session_id}.md"
else
    receipt_path=".claude/.cert/<your-session-id>.md  (session_id not in hook input — use the id surfaced in your session env)"
fi

# Compose the additionalContext body. Plain text; jq encodes safely below.
body="================================================================
BRUNO CERT CHALLENGE — required before any Edit/Write/NotebookEdit
================================================================

Gate mode is currently: ${gate_mode}
  - warn  → tool calls proceed, you get a CERT INCOMPLETE warning in
            context each time you try to Edit/Write without a valid receipt.
  - deny  → tool calls are hard-blocked until a valid receipt exists.

Your task: write a cert receipt file at:
  ${receipt_path}

It must contain all ten required H2 section headers (## 1. through ## 10.),
exactly as listed in .claude/CERTIFICATION.md, with substantive body text.
Total file size > 1500 bytes.

The receipt-write itself is gate-exempt: you CAN Write to
.claude/.cert/*.md even before cert is complete (so you can write your
own receipt). All other Edit/Write/NotebookEdit calls are checked.

Verified toolchain (probe it live for section 5 — do not recall it):
  Xcode 26.3 / Swift 6.2.4 / tvOS 26.2 SDK. Run 'xcodebuild -version'.

----------------------------------------------------------------
CERTIFICATION.md (canonical ritual, inline copy):
----------------------------------------------------------------

${cert_doc}

----------------------------------------------------------------
PRELUDE — recent repo state for your cert:
----------------------------------------------------------------

git log --oneline -20:
${git_log}

Heartbeat: docs/PROJECT_TRACKER.md is the project status of record;
docs/BRUNO_NAV_MAP.md + docs/BRUNO_CODE_MAP.md are the surface/architecture
maps. Trace your change through them before editing (CLAUDE.md).

----------------------------------------------------------------
${worktree_block}
----------------------------------------------------------------

================================================================
End of cert challenge. Produce your receipt before Edit/Write.
================================================================"

jq -nc --arg ctx "$body" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'

exit 0
