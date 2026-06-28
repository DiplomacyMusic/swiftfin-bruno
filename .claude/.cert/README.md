# Cert receipts

This directory holds per-session certification receipts and the mode-flip
config for the Bruno cert gate. See `.claude/CERTIFICATION.md` for the full
ritual and `.claude/hooks/pretooluse_cert_gate.sh` for the enforcement.

## Files here

- `mode` — single word, `warn` or `deny`. Controls whether the PreToolUse
  gate hard-blocks (`deny`) or just warns (`warn`). Tracked in git.
- `<session-id>.md` — receipts written by each Claude Code session.
  Gitignored (session-ephemeral).
- `.gitkeep` — keeps the dir alive in git.

## Flipping the gate mode

The cert system **ships in `warn`** — the same checks run, but failures
emit a strong `CERT INCOMPLETE` warning in context instead of blocking the
tool call. This is the advisory rollout phase: let the receipt format
settle across a few sessions, drop ceremony that doesn't earn its keep,
then flip to hard enforcement.

To hard-block Edit/Write/NotebookEdit until a valid receipt exists:

```
echo deny > .claude/.cert/mode
```

To go back to advisory:

```
echo warn > .claude/.cert/mode
```

No script edit, no restart. The gate reads this file fresh on every
PreToolUse. If anything ever bricks a session (false-positive denials, a
hook bug), `echo warn` is the instant escape hatch.

## Receipt validity

A receipt at `.claude/.cert/<session-id>.md` is considered valid when:

1. It exists.
2. It contains all ten required H2 section headers exactly as listed in
   `.claude/CERTIFICATION.md` (numbered `## 1.` through `## 10.`).
3. Total file size is > 1500 bytes (prevents ten-empty-header stubs).
4. Section content fingerprints pass:
   - **§5** — a real toolchain probe token (`Xcode 2…` / `Build version` /
     `Swift version` / `swiftlang`) or a specific toolchain-failure token.
   - **§6** — at least one `file:line` citation; no skip/laziness phrasing
     on the `bruno-expert` line (bruno-expert is mandatory every session).
   - **§7** — names an `INV-n` rule or declares the `touch-only` exemption.
   - **§10** (worktrees only) — a concrete build token (`xcodebuild` /
     `Swiftfin tvOS` / `cd <worktree>`) or a no-build phrase (`docs-only`).

If any check fails, the gate emits `CERT INCOMPLETE` listing what's
missing. In `warn` mode the tool call still proceeds; in `deny` it's
blocked.

## Gate-exempt paths

So the gate can never trap its own bootstrap, these writes are allowed
without a cert: `.claude/.cert/*` (your receipt), `.claude/CERTIFICATION.md`,
`.claude/settings.json` / `settings.local.json`, `.claude/hooks/*.sh`,
`.claude/commands/*.md`.

## Cleanup

Old receipts pile up but are tiny (and gitignored). Manual sweep whenever:

```
find .claude/.cert -name '*.md' ! -name 'README.md' -mtime +14 -print
```

Add `-delete` to actually remove them.
