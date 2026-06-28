---
description: Walk through the Bruno thread certification ritual and write the receipt file
---

You are being asked to produce a Bruno cert receipt before any
code-touching tool call is allowed (or to refresh one mid-session). The
canonical ritual is `.claude/CERTIFICATION.md`; this command captures the
prelude and emits the template so the gate costs minutes, not the whole
session.

**Step 1 — capture the prelude.** Run these in parallel:

- Bash: `xcodebuild -version` and `swift --version` — the live toolchain
  probe. Paste the literal output into section 5. (Verified toolchain is
  Xcode 26.3 / Swift 6.2.4 / tvOS 26.2 SDK per `BRUNO_NOTES.md` §Toolchain;
  the probe proves it resolves right now.)
- Bash: `git -C "$(pwd)" log --oneline -20` — recent commit context.
- Bash: grep the `// INV-` sites your change will touch, e.g.
  `git diff --name-only` then
  `grep -rnE '// INV-[0-9]|/// INV-[0-9]' <those files>` — feed section 7.
- Read `.claude/CERTIFICATION.md` — confirm the ten required H2 headers
  and the worktree-conditional rule on section 10's build token.

**Step 2 — dispatch experts.** Dispatch `bruno-expert` for an
architecture / code-flow briefing of your focus area (where the code
lives, current tracker state, the contract, with `file:line` citations) —
this is **mandatory every session**. If the change touches Swift /
SwiftUI / focus-engine / build mechanics (nearly all code changes), also
dispatch `swift-xcode-expert`; for a pure-docs diff you may skip it with a
named reason. Wait for their returns before writing the receipt — paste
bruno-expert's `file:line` citations into section 6.

**Step 3 — write the receipt.** Resolve your session_id from the
SessionStart hook output already in your context (the BRUNO CERT CHALLENGE
block names the exact receipt path). Use the `Write` tool to create that
file containing all ten sections:

```
## 1. Bruno purpose
## 2. Feature focus
## 3. Mechanic
## 4. Surfaces touched
## 5. Build / toolchain probe
## 6. Expert dispatch
## 7. Invariants acknowledged
## 8. Determinism & perf
## 9. Self-verification plan
## 10. Execution environment
```

The SessionStart hook already surfaced the worktree fact (yes/no, branch,
paths) and the worktree-scoped `xcodebuild` command in your context. Use
it to fill section 10 honestly — the owner builds `main` in Xcode, so a
worktree change is not what he builds until merged; give a worktree-scoped
build command or an explicit docs-only opt-out.

The `.claude/.cert/*.md` path is exempt from the cert gate, so Write to it
works even before cert is complete. Total receipt must exceed 1500 bytes
(substantive content per section).

**Step 4 — verify the gate sees a valid receipt.** After Write, try a
trivial Edit on a non-cert file (e.g. a typo fix-and-restore on a README).
The gate runs. In `warn` mode, no `CERT INCOMPLETE` warning means pass; in
`deny` mode, the Edit going through means pass.

**Do NOT skip any section.** Cite a rule only if your change touches it —
fabricated INV acknowledgements or a hallucinated `bruno-expert` return
fail the section's intent. If you cannot honestly fill a section, stop and
ask Daniel what to do instead of fabricating.
