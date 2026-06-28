# Bruno Certification Plan

> **Status: BUILT (shipping in `warn` mode).** The gate is implemented and live. Assets:
> `.claude/CERTIFICATION.md` (canonical 10-section ritual), `.claude/hooks/pretooluse_cert_gate.sh`
> (the gate) + `.claude/hooks/sessionstart_cert.sh` (prelude injector), wired in `.claude/settings.json`;
> `.claude/.cert/{mode,README.md}`; `/bruno-cert` scaffold at `.claude/commands/bruno-cert.md`. Mode is
> `warn` (advisory) per the rollout plan below — flip `.claude/.cert/mode` to `deny` for hard enforcement.
> This doc is the original design rationale; `.claude/CERTIFICATION.md` is the operative spec on any drift.
> Modeled on the SlateRunner certification system (`~/Documents/Claude/Projects/SlateRunner`).

## Why Bruno needs this

Bruno's tvOS Home is fast and correct because of **invisible, load-bearing rules** — the ten perf
invariants (INV-1..10), the deterministic seeded `BrunoHomePlan.build`, the centralized `brunoRouteToShowAll`
seam, and a thin-fork doc web that drifts easily. A fresh thread reads "add a shelf" as simple, misses the
determinism contract or an INV site, and the breakage surfaces weeks later on a real device. SlateRunner's
answer is a **certification receipt** an agent must produce *before* it edits — proof, not promises. This
plan ports that idea to Bruno. (Bad sessions in this repo have been exactly this failure mode.)

## What a Bruno change certifies

A cert asserts five things about a proposed change:

1. **Build/compile** — the tvOS scheme builds clean on the verified toolchain (`BRUNO_NOTES.md` §Toolchain);
   no errors, no deprecated-API use.
2. **Performance invariants** — the diff violates none of INV-1..10 (`docs/BRUNO_PERF_INVARIANTS.md`).
3. **Scroll/focus correctness** — no held-repeat freeze (INV-10), no vertical-scroll hitch; on-device
   evidence when a scroll/focus surface is touched (`docs/BRUNO_PERF_HANDOFF.md` + `BRUNO_PERF_LOGGING.md`).
4. **Determinism** — `BrunoHomePlan` stays pure: same `(seed, snapshot)` ⇒ same plan
   (`BrunoHomePlan+SelfCheck`), proven across a fixed seed set for any plan-touching change.
5. **Doc/reference integrity** — no claim in `CLAUDE.md` / `BRUNO_CODE_MAP.md` / `BRUNO_NAV_MAP.md` /
   `BRUNO_PERF_INVARIANTS.md` / `PROJECT_TRACKER.md` is made false by the change; drift is flagged (owner
   decides the fix).

## The five checks

| Check | What it does | Grounded in |
|---|---|---|
| **Build validator** | headless `xcodebuild` on `Swiftfin tvOS`; parse for `error:` / `deprecated` | `BRUNO_NOTES.md` §Toolchain |
| **INV scanner** | grep the diff for `// INV-[0-9]` sites; for each touched site, verify the rule still holds | `BRUNO_PERF_INVARIANTS.md`, `BrunoShelfMetrics` |
| **Scroll/focus diagnostician** | if a scroll/focus surface is touched, require an on-device frame-time + Δy log (no >100 ms stall, no focus jump); else an explicit "touch-only" exemption | `BRUNO_PERF_HANDOFF.md` + `BRUNO_PERF_LOGGING.md` (DEBUG HUD) |
| **Determinism asserter** | run `BrunoHomePlan` self-check over a fixed seed set; PASS/FAIL + plan diff on regression | `BrunoHomePlan+SelfCheck.swift` |
| **Doc auditor** | scan the canonical docs for claims about the changed files; flag staleness (do not auto-edit) | `BRUNO_CODE_MAP.md`, `BRUNO_NAV_MAP.md`, `CLAUDE.md` |

## The cert receipt

A markdown receipt at `.claude/.cert/<session-id>.md` with these sections (parallel to SlateRunner,
tailored to Bruno). Keep it real — no fake acknowledgements; cite a rule only if the change touches it.

1. **Bruno purpose** — one paragraph (the tvOS fork + Home pipeline + perf contract).
2. **Feature focus** — one line: what you're building + the map section it lives in.
3. **Mechanic** — restated requirement, data flow, input/output shapes.
4. **Surfaces touched** — upstream feeders + downstream consumers of the change.
5. **Build probe** — raw headless `xcodebuild` output (or the specific toolchain check).
6. **Expert dispatch** — `bruno-expert` (architecture/code-flow) + `swift-xcode-expert` (Swift/SwiftUI/tvOS),
   both every session; conditional experts only when relevant.
7. **Invariants acknowledged** — ≥1 INV rule the change must respect (one sentence each), or an explicit
   "touch-only, no INV sites."
8. **Determinism & perf** — does it preserve `BrunoHomePlan` determinism? Any scroll/focus risk? Risk or proof.
9. **Self-verification plan** — concrete checks: build-log parse, seed-set assert, on-device log (if needed),
   doc-audit findings.
10. **Execution environment** — worktree vs primary, the Xcode scheme + device/sim, on-device prereqs
    (`DEPLOYMENT_HANDOFF.md`).

## Enforcement

- **`.claude/.cert/mode`** — `warn` (advisory) or `deny` (hard-block). Start at `warn`; flip to `deny` once
  the format settles.
- **`.claude/hooks/pretooluse_cert_gate.sh`** — a PreToolUse hook (adapted from SlateRunner) that blocks
  `Edit`/`Write`/`NotebookEdit` until the receipt exists with all ten headers and exceeds a min size. Honors
  the mode file.
- **`/bruno-cert` scaffold** — captures the prelude (headless build output, recent Bruno git log, `// INV-`
  sites in the diff, a `bruno-expert` summary) and emits the receipt template, so the gate costs ~minutes.
- **Fast path** — pure recolor/string/comment diffs declare "touch-only, no perf/determinism risk" in §7–8
  and skip the on-device check. Keeps ceremony proportional to risk.

## SlateRunner → Bruno mapping

| SlateRunner | Bruno equivalent |
|---|---|
| Pro Tools MCP live probe (§5) | headless `xcodebuild` toolchain probe |
| slate-expert / protools-expert / soundflow-expert dispatch | `bruno-expert` + `swift-xcode-expert` (+ conditional) |
| "pitfalls acknowledged" | "invariants acknowledged" (INV-1..10) |
| PTSL backgroundability proof | scroll/focus on-device evidence (or touch-only exemption) |
| SlateFX deterministic builder | `BrunoHomePlan.build` determinism self-check |
| RUNNING_THE_TOOLS / PRODUCT_SPEC sync | the canonical doc set (`BRUNO_CODE_MAP` / `NAV_MAP` / `CLAUDE.md`) |
| `.claude/.cert/mode` + pretooluse gate | same, ported |
| `/cert` command | `/bruno-cert` scaffold |

## Rollout

1. Build `/bruno-cert` scaffold + the receipt template; run in **`warn`** mode for a few sessions.
2. Tune sections (drop ceremony that doesn't earn its keep; keep the five checks).
3. Flip to **`deny`** once the format is stable and the owner wants hard enforcement.
4. Revisit after the feature backlog lands (the cert is most valuable while Home/shelf internals churn).
