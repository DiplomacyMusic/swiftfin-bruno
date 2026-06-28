#!/usr/bin/env bash
# PreToolUse cert gate for Bruno.
#
# Fires on every Edit, Write, and NotebookEdit tool call. Validates that
# the current session has produced a cert receipt at
# .claude/.cert/<session-id>.md containing all ten required H2 section
# headers from .claude/CERTIFICATION.md, with total file size > 1500
# bytes (prevents ten-empty-header stub fakes), plus content fingerprints
# on sections 5, 6, 7 and (in worktrees) 10.
#
# Mode is read fresh on every call from .claude/.cert/mode:
#   - "warn" (or file missing) → emit additionalContext with the CERT
#     INCOMPLETE message, exit 0 (tool call proceeds).
#   - "deny" → emit permissionDecision:"deny" with the same message,
#     hard-blocking the tool call.
#
# Receipt-path exemption: writes to the cert receipt itself, the canonical
# doc, the cert README/mode, the gate config, hook scripts, and commands
# are allowed silently (otherwise the agent could not produce its own
# receipt or fix the gate).
#
# Defensive: any internal error (missing jq, malformed input, missing
# project dir) exits 0 silently. This hook should NEVER brick a session
# due to its own bugs.

set -u

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"

[ -d "$project_dir/.claude" ] || exit 0

# Exemption: gate-internal files. Writing the cert receipt, the canonical
# doc, the README/mode, the gate config, hook scripts, or commands must
# work without a cert — otherwise bootstrapping or fixing the gate (or
# writing your own receipt) is impossible.
case "$file_path" in
    */.claude/.cert/*.md|*/.claude/.cert/README.md|*/.claude/.cert/mode)
        exit 0
        ;;
    */.claude/CERTIFICATION.md)
        exit 0
        ;;
    */.claude/settings.json|*/.claude/settings.local.json)
        exit 0
        ;;
    */.claude/hooks/*.sh|*/.claude/commands/*.md)
        exit 0
        ;;
esac

mode_path="$project_dir/.claude/.cert/mode"
if [ -f "$mode_path" ]; then
    gate_mode="$(tr -d '[:space:]' < "$mode_path")"
else
    gate_mode="warn"
fi
[ -z "$gate_mode" ] && gate_mode="warn"

# Without a session_id we can't locate the receipt. Don't break the
# session — exit 0 silently and let the agent proceed.
[ -n "$session_id" ] || exit 0

receipt_path="$project_dir/.claude/.cert/${session_id}.md"

# Required H2 headers from CERTIFICATION.md.
required_headers=(
    "## 1. Bruno purpose"
    "## 2. Feature focus"
    "## 3. Mechanic"
    "## 4. Surfaces touched"
    "## 5. Build / toolchain probe"
    "## 6. Expert dispatch"
    "## 7. Invariants acknowledged"
    "## 8. Determinism & perf"
    "## 9. Self-verification plan"
    "## 10. Execution environment"
)

missing=()
size=0
exists="no"

if [ -f "$receipt_path" ]; then
    exists="yes"
    size="$(wc -c < "$receipt_path" | tr -d '[:space:]')"
    for header in "${required_headers[@]}"; do
        grep -Fq "$header" "$receipt_path" || missing+=("$header")
    done

    # Section content validation. Only runs when all headers are present --
    # otherwise the structural-missing feedback is more useful than content
    # nitpicks layered on top.
    if [ "${#missing[@]}" -eq 0 ]; then
        # Worktree detection (mirrors the SessionStart hook). Compares
        # git-dir vs git-common-dir; if they differ, we're in a worktree.
        is_worktree="no"
        gate_git_dir="$(git -C "$project_dir" rev-parse --git-dir 2>/dev/null)"
        gate_common_dir="$(git -C "$project_dir" rev-parse --git-common-dir 2>/dev/null)"
        if [ -n "$gate_git_dir" ] && [ -n "$gate_common_dir" ] && [ "$gate_git_dir" != "$gate_common_dir" ]; then
            is_worktree="yes"
        fi

        # Helpers for token/phrase checks.
        #
        # strip_inline_backticks: removes inline `...` spans. Used for
        # token checks that should not be fooled by meta-references
        # (e.g. "the gate looks for `Xcode`" should NOT count as a real
        # probe).
        #
        # strip_all: also removes fenced ```...``` code blocks. Used ONLY
        # for laziness-phrase checks where references to the lazy phrase
        # as a string (inline or in a code block) are legitimate
        # meta-discussion.
        #
        # DO NOT use strip_all for POSITIVE token checks like section 5's
        # toolchain version -- legitimate probe output lives in code
        # blocks and stripping them produces false-negative gate failures.
        strip_inline_backticks() {
            printf '%s\n' "$1" | sed 's/`[^`]*`//g'
        }
        strip_all() {
            printf '%s\n' "$1" | \
                awk 'BEGIN{in_block=0} /^```/{in_block=1-in_block; next} !in_block{print}' | \
                sed 's/`[^`]*`//g'
        }

        # Section 5: must show evidence of a real toolchain probe. Either a
        # version token (probe succeeded) OR a specific toolchain-failure
        # token (probe attempted, error captured). Strip inline backticks
        # only -- fenced code blocks contain legitimate probe output.
        sec5="$(awk '/^## 5\. Build \/ toolchain probe/{flag=1; next} /^## 6\./{flag=0} flag' "$receipt_path")"
        if [ -n "$sec5" ]; then
            sec5_tokens="$(strip_inline_backticks "$sec5")"
            if ! echo "$sec5_tokens" | grep -qE "Xcode 2|Build version|Swift version|swiftlang|xcodebuild: error|xcode-select|unable to find utility|Command line tools"; then
                missing+=("Section 5 content: no evidence of a real toolchain probe. Run 'xcodebuild -version' (and/or 'swift --version') and paste the output. Need a version token ('Xcode 2…', 'Build version', 'Swift version', 'swiftlang') OR a specific toolchain-failure token ('xcodebuild: error', 'xcode-select', 'unable to find utility', 'Command line tools'). Prose-only skipping fails the gate.")
            fi
        fi

        # Section 6: bruno-expert is MANDATORY every session. The section
        # must include its return with at least one file:line citation, and
        # must not show skip/laziness phrasing on the bruno-expert line.
        sec6="$(awk '/^## 6\. Expert dispatch/{flag=1; next} /^## 7\./{flag=0} flag' "$receipt_path")"
        if [ -n "$sec6" ]; then
            sec6_prose="$(strip_all "$sec6")"

            # Smoking-gun skip-rationalization phrases in bare prose.
            if echo "$sec6_prose" | grep -qiE "justified skip|would burn|burn 30 sec"; then
                missing+=("Section 6 content: contains skip-rationalization phrase ('justified skip', 'would burn', 'burn 30 sec') in bare prose. bruno-expert is MANDATORY every session -- no exceptions. (Backticked references and fenced code blocks are stripped before this check.)")
            fi
            # The line containing the first bruno-expert mention must NOT
            # show a skip pattern. swift-xcode-expert MAY be skipped for
            # docs-only diffs, so its line is not checked here.
            bruno_line="$(echo "$sec6" | grep -i "bruno-expert" | head -1)"
            bruno_line_prose="$(strip_all "$bruno_line")"
            if [ -n "$bruno_line_prose" ] && echo "$bruno_line_prose" | grep -qiE "not dispatched|: skipped|: declined|: n/a|: optional"; then
                missing+=("Section 6 content: bruno-expert line shows a skip pattern ('not dispatched' / 'declined' / 'n/a' / 'optional' / 'skipped') in bare prose. bruno-expert dispatch is MANDATORY every session.")
            fi
            # At least one file:line citation. bruno-expert favors precise
            # file:line citations; the receipt must include them verbatim.
            # (Space-containing paths like 'Swiftfin tvOS/...' still yield a
            # matching substring after the space, e.g. 'Views/.../X.swift:42'.)
            if ! echo "$sec6" | grep -qE "[A-Za-z][A-Za-z0-9_./-]*\.(swift|md|json|toml|yaml|yml|sh|plist|xcconfig):[0-9]+"; then
                missing+=("Section 6 content: no file:line citation found. bruno-expert cites file:line on its claims (e.g. Shared/Objects/Bruno/BrunoHomePlan.swift:142, docs/BRUNO_NAV_MAP.md:88); paste the verbatim citations.")
            fi
        fi

        # Section 7: must name at least one INV rule OR declare the
        # explicit touch-only fast-path exemption.
        sec7="$(awk '/^## 7\. Invariants acknowledged/{flag=1; next} /^## 8\./{flag=0} flag' "$receipt_path")"
        if [ -n "$sec7" ]; then
            if ! echo "$sec7" | grep -qiE "INV-[0-9]|touch-only|no INV site|no INV sites|no invariant site"; then
                missing+=("Section 7 content: name at least one perf invariant ('INV-1'..'INV-10', docs/BRUNO_PERF_INVARIANTS.md) the change respects, OR declare the fast-path exemption literally ('touch-only -- no INV sites, no perf/determinism risk').")
            fi
        fi

        # Section 10: worktree-only check. When worktree=yes, the receipt
        # must show a CONCRETE build token, not just prose awareness --
        # because the owner builds 'main' in Xcode, so worktree code is not
        # what his Xcode builds, and threads consistently hand him a command
        # that verifies the wrong tree. Acceptable tokens:
        #   xcodebuild        -- a headless build scoped to the worktree
        #   Swiftfin tvOS     -- the scheme name (implies a real build cmd)
        #   "cd "             -- a worktree-scoped invocation
        #   no-build phrases  -- explicit docs-only opt-out
        if [ "$is_worktree" = "yes" ]; then
            sec10="$(awk '/^## 10\. Execution environment/{flag=1; next} /^## [0-9]/{flag=0} flag' "$receipt_path")"
            if [ -n "$sec10" ]; then
                if ! echo "$sec10" | grep -qiE "xcodebuild|Swiftfin tvOS|cd |docs-only|no build|pure markdown|no Xcode"; then
                    missing+=("Section 10 content (worktree): no concrete build token. When worktree=yes, section 10 must show a real build path ('xcodebuild' scoped to the worktree, the scheme 'Swiftfin tvOS', or a 'cd <worktree>' invocation) OR an explicit no-build phrase ('docs-only', 'no build', 'pure markdown', 'no Xcode'). The owner builds 'main' in Xcode -- this worktree's code is not what he builds until merged, so a vague 'ask Daniel to run it' verifies the wrong tree.")
                fi
            fi
        fi
    fi
fi

# Pass conditions: file exists, all checks pass, size > 1500 bytes.
if [ "$exists" = "yes" ] && [ "${#missing[@]}" -eq 0 ] && [ "$size" -gt 1500 ]; then
    exit 0
fi

# Build the CERT INCOMPLETE message.
body="CERT INCOMPLETE

Tool: ${tool_name}
Session: ${session_id}
Required receipt path: .claude/.cert/${session_id}.md

Status:
  - receipt exists: ${exists}
  - receipt size:   ${size} bytes (need > 1500)
  - missing checks: ${#missing[@]} of ${#required_headers[@]} headers + content"

if [ "${#missing[@]}" -gt 0 ]; then
    body+=$'\n\nMissing / failed:'
    for h in "${missing[@]}"; do
        body+=$'\n  - '"$h"
    done
fi

body+=$'\n\nFix: write your cert receipt with all required sections per .claude/CERTIFICATION.md.
You can invoke /bruno-cert for a scaffold, or write the receipt directly with the Write tool
(the path .claude/.cert/'"${session_id}"'.md is exempt from this gate).'

if [ "$gate_mode" = "deny" ]; then
    jq -nc --arg reason "$body" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
else
    # warn mode: surface the warning in context but allow the tool call.
    jq -nc --arg ctx "$body" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
fi

exit 0
