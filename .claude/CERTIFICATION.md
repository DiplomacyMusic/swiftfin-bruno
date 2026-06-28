# Bruno thread certification ritual

Every new Claude Code thread in this repo must produce a **cert receipt**
before any code-touching tool call (Edit, Write, NotebookEdit) is allowed.

The receipt is a single markdown file at:

```
.claude/.cert/<session-id>.md
```

It must contain all ten sections below, each as an `## N. <title>` H2
header, with substantive body text. Total file size must exceed 1500
bytes (prevents header-only stub fakes).

The PreToolUse gate at `.claude/hooks/pretooluse_cert_gate.sh` enforces
this. In `mode=warn` it surfaces a strong warning. In `mode=deny` it
hard-blocks Edit/Write/NotebookEdit. See `.claude/.cert/README.md` for
how to flip modes. The system ships in **`warn`** — advisory while the
format settles; flip to `deny` once it's stable.

The session_id is supplied to your hook input — it's also visible in the
SessionStart hook output that injected this doc into your context.

---

## Why this exists

Bruno's tvOS Home is fast and correct because of **invisible, load-bearing
rules** — the ten perf invariants (`INV-1..10` in
`docs/BRUNO_PERF_INVARIANTS.md`), the deterministic seeded
`BrunoHomePlan.build` (same `(seed, snapshot)` ⇒ same plan), the
centralized `brunoRouteToShowAll` "show all" seam, and a thin-fork doc web
that drifts easily. A fresh thread reads "add a shelf" as simple, misses
the determinism contract or an `// INV-n` site, and the breakage surfaces
weeks later on a real device.

Cert closes that loop by mechanically requiring the grounding work to be
done — and attested with evidence — before a single source file can be
touched. The receipt is **proof, not promises.** Cite a rule only if your
change touches it; fabricated acknowledgements are worse than none.

---

## The ten required sections

Each section has a goal and a machine check (what the gate scans for).

### `## 1. Bruno purpose`

**Goal:** One short paragraph. The tvOS-only Swiftfin fork, the Home
pipeline (`BrunoHomePlan` seeded descriptor → `BrunoHomeViewModel` paging
VM → `BrunoShelfView`/`PosterHStack` render), and the perf contract that
keeps scroll/focus fast.

**Machine check:** literal header `## 1. Bruno purpose` present;
contributes to the >1500-byte total.

### `## 2. Feature focus`

**Goal:** One line — what you're building + the map section it lives in.
E.g. `Collections shelf — docs/BRUNO_NAV_MAP.md §Collections; engine in Shared/Objects/Bruno/`.

**Machine check:** literal header `## 2. Feature focus` present.

### `## 3. Mechanic`

**Goal:** ~150 words. Restate the requirement, the data flow, and the
input/output shapes. Where in the one connected pipeline does the change
sit — is it a new seeded descriptor in `BrunoHomePlan`, a VM/paging
change, a render change, or a routing change through
`brunoRouteToShowAll`? Forces you to trace the change before editing.

**Machine check:** literal header `## 3. Mechanic` present.

### `## 4. Surfaces touched`

**Goal:** The upstream feeders and downstream consumers of the change.
A shelf change ripples: descriptor → VM → row view → "show all"
destination. Name the exact files on each side of the boundary
(`file:line` where you can).

**Machine check:** literal header `## 4. Surfaces touched` present.

### `## 5. Build / toolchain probe`

**Goal:** Prove the verified toolchain resolves **right now**. Run
`xcodebuild -version` (and/or `swift --version`) and paste the literal
output. This is a fast reachability probe, NOT the full compile — the
receipt is written *before* you edit, so there is nothing to compile yet.
The full compile gate belongs in §9 (run after editing).

The verified toolchain is **Xcode 26.3 / Swift 6.2.4 / tvOS 26.2 SDK**
(`BRUNO_NOTES.md` §Toolchain). If the toolchain genuinely cannot be
probed in this harness, paste the **literal error text** so the failure
is documented.

**Machine check:** literal header `## 5. Build / toolchain probe`
present; section content must contain a toolchain-version token
(`Xcode 2…`, `Build version`, `Swift version`, or `swiftlang`) OR a
specific toolchain-failure token (`xcodebuild: error`, `xcode-select`,
`unable to find utility`, `Command line tools`). Inline `` `backticks` ``
are stripped before the check (meta-references to the tokens don't
count). Prose-only skipping fails the gate.

### `## 6. Expert dispatch`

**Goal:** `bruno-expert` is dispatched **every session** for an
architecture / code-flow briefing — no exceptions. It surfaces where the
code lives, the current tracker state, and the contract for your area,
with precise `file:line` citations. Paste its return (with the citations
intact) in this section.

`swift-xcode-expert` is dispatched whenever the change touches Swift /
SwiftUI / focus-engine / build mechanics — i.e. nearly all code changes.
For a **pure docs / markdown** diff you may skip it with a named reason.
Other conditional experts only when relevant.

When you skip a conditional expert, name the area and why:

```
- swift-xcode-expert: not dispatched — pure docs change, no Swift touched.
```

**Machine check:** literal header `## 6. Expert dispatch` present;
section content must contain at least one `file:line` citation (a path
with a `.swift`/`.md`/`.json` extension followed by `:` and a line
number); the line containing the first `bruno-expert` mention must NOT
contain a skip pattern (`not dispatched`, `skipped`, `declined`, `n/a`,
`optional`) in bare prose; the section must NOT contain laziness phrases
(`justified skip`, `would burn`, `burn 30 sec`) in bare prose. Inline
backticks and fenced code blocks are stripped before the phrase checks
(quoting the phrases as strings is fine).

### `## 7. Invariants acknowledged`

**Goal:** Name **≥1 perf invariant** (`INV-1..10`,
`docs/BRUNO_PERF_INVARIANTS.md`) your change must respect — one sentence
each on the trap and why it applies to your diff. Grep your change for
`// INV-n` / `/// INV-n` sites; for each site touched, state how the rule
still holds.

If the change touches **no** scroll/focus/render surface and no `INV`
site, declare the fast-path exemption explicitly:

```
touch-only — no INV sites in the diff, no perf/determinism risk.
```

**Machine check:** literal header `## 7. Invariants acknowledged`
present; section content must contain an `INV-` reference OR an explicit
touch-only phrase (`touch-only`, `no INV site`, `no INV sites`,
`no invariant site`).

### `## 8. Determinism & perf`

**Goal:** Short paragraph. Does the change touch `BrunoHomePlan.build`
(real signature `build(seed:snapshot:now:)` — `now` is injected so the
plan is wall-clock-independent) or anything it calls? If yes, it MUST
preserve purity — same `(seed, snapshot, now)` ⇒ same plan — and you
commit to the `BrunoHomePlan.selfCheckPassed()` assert (see §9). If it
touches a scroll/focus surface, state the perf risk and how you'll prove
no >100 ms stall / no focus jump. If neither, say so plainly (the
fast-path "no determinism risk, no scroll/focus surface touched").

**Machine check:** literal header `## 8. Determinism & perf` present.

### `## 9. Self-verification plan`

**Goal:** Concrete checks you will run to verify your own output — not
"I'll ask Daniel." At minimum:

- **Compile gate** — the full headless build, parsed for `error:`
  (compile-verification only; a *runnable* sim build needs ad-hoc
  signing — `BRUNO_NOTES.md` §Toolchain):
  ```
  xcodebuild -project Swiftfin.xcodeproj -scheme "Swiftfin tvOS" \
    -destination 'generic/platform=tvOS Simulator' -skipMacroValidation \
    build CODE_SIGNING_ALLOWED=NO
  ```
- **Determinism assert** (plan-touching changes) —
  `BrunoHomePlan.selfCheckPassed()` (the DEBUG assert fired in
  `BrunoHomeViewModel.init`) fixes a seed pair + injected `now` and
  asserts same-input stability, seed-variance, no-adjacent-same-kind,
  dedupe, and the sparse-group drop. Confirm it still passes; on a
  regression, capture the failing assertion + plan diff.
- **On-device evidence** (scroll/focus surfaces) — a frame-time + Δy log
  showing no >100 ms stall and no focus jump
  (`docs/BRUNO_PERF_HANDOFF.md` + `docs/BRUNO_PERF_LOGGING.md`), or an
  explicit "touch-only, no scroll/focus surface" exemption.
- **Doc audit** — scan `CLAUDE.md` / `BRUNO_CODE_MAP.md` /
  `BRUNO_NAV_MAP.md` / `BRUNO_PERF_INVARIANTS.md` / `PROJECT_TRACKER.md` /
  `BRUNO_NOTES.md` for any claim the change makes false; flag drift
  (owner decides the fix — do not auto-edit canonical docs).

**Machine check:** literal header `## 9. Self-verification plan` present.

### `## 10. Execution environment`

**Goal:** State the worktree/branch context and the build implications
for any "ask Daniel to test" command you'll hand him. The SessionStart
hook auto-surfaces the worktree fact (yes/no, branch, paths).

**The load-bearing Bruno fact:** the owner builds **`main`** in Xcode
(see the PR workflow — worktree → PR → owner merges). Code in *this
worktree* is NOT what his Xcode builds until it's merged to `main`. So
any "run this to verify" must either be a headless `xcodebuild` against
the worktree path, or you must say the change has to land on `main`
first. Don't hand him a command that builds the wrong tree.

Two required facts:

1. **Worktree status** — are we in a worktree (`yes`/`no`)? If yes, the
   worktree name and branch.
2. **Build-resolution fact** — Xcode's open project / the owner's normal
   Run targets `main`, not this worktree. To verify this worktree's code
   headlessly, scope `xcodebuild` to the worktree path; to verify it in
   Xcode, it must be merged to `main` first.

**When worktree=yes, include a CONCRETE token:** the `xcodebuild`
command scoped to the worktree, the scheme name `Swiftfin tvOS`, the
worktree path / a `cd` into it, OR an explicit no-build phrase
(`docs-only`, `no build`, `pure markdown`, `no Xcode`).

**Machine check:** literal header `## 10. Execution environment`
present; when worktree=yes, section content MUST contain one of:
`xcodebuild`, `Swiftfin tvOS`, `cd ` (worktree-scoped command), OR an
explicit no-build phrase (`docs-only`, `no build`, `pure markdown`,
`no Xcode`). When worktree=no, header presence is sufficient.

---

## Worked example header set

A valid receipt's first line of each section looks exactly like:

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

Missing any one of these → gate fails.
Total file content under 1500 bytes → gate fails.

---

## The `/bruno-cert` slash command

If you want a scaffold instead of writing from scratch, invoke
`/bruno-cert`. It runs the prelude captures (toolchain probe, recent git
log, the `// INV-` sites in your diff, a `bruno-expert` briefing) and
echoes the template for you to fill in.

---

## What `mode` controls

The file `.claude/.cert/mode` flips the gate between `warn` (advisory
context injected, tool call proceeds) and `deny` (tool call blocked with
the same message). See `.claude/.cert/README.md` for flip instructions.

The gate read happens fresh on every PreToolUse — no restart needed.
