# AutoCorrect shared work log

This is the durable handoff between Claude, Codex and the owner. Read [CLAUDE-HANDOFF.md](CLAUDE-HANDOFF.md) for the full conversation/implementation history and root [CLAUDE.md](../CLAUDE.md) for mandatory logging instructions. Use dates with timezone and distinguish facts from hypotheses. Never record private typing or credentials.

## Current resume state

- **As of:** September 30, 2026, America/New_York.
- **Latest task:** Create the Claude handoff and ongoing logging protocol; documentation only, complete in the accompanying documentation commit.
- **Runtime baseline:** `main` at `3ce0cc69e375782e057e7e0d59338bf4b37414eb`, plus the handoff documentation commit. Use `git log` for its final hash.
- **Installed / public app:** 0.3.7 in `/Applications/AutoCorrect.app`; [v0.3.7 prerelease](https://github.com/markoderic/autocorrect/releases/tag/v0.3.7). No runtime or version changes in this documentation task.
- **Validation:** Prior 154 local tests passed; source CI [36633237549](https://github.com/markoderic/autocorrect/actions/runs/36633237549) successful, rechecked September 30. Installed permission/listener/layout/login diagnostics also rechecked successfully.
- **Known blockers:** Developer ID/notarization credentials absent at last inventory; real-keyboard app matrix, independent accuracy benchmark and sustained resource measurements still pending. Earlier user-confirmed Claude 0.2.3 result is not a current all-app pass.
- **Next concrete action for Claude:** Inspect repo state and current engine/edit paths, audit existing accuracy fixtures and negative cases, choose a reproducible high-impact failure, add a failing regression, implement a bounded fix and log its evidence. Begin physical-input matrix and independent evaluation without weakening text-preservation guards.
- **Not authorized:** Sending/posting LinkedIn content. No marketing task is active.

## Entry template — copy for every task

```markdown
### YYYY-MM-DD HH:MM TZ — agent — short task title

- Status: IN PROGRESS / COMPLETE / PARTIAL / BLOCKED / NO CHANGE
- Request and scope:
- Starting branch/commit; existing local changes:
- Findings and root cause (or hypothesis, clearly labeled):
- Changes and affected files:
- Verification: commands, OS/app versions, pass/fail/skip counts and evidence links. Separate deterministic/native-engine tests from real keyboard interaction.
- Accuracy/performance comparison: baseline versus result, corpus/measurement limits, false-positive tradeoffs; or not measured.
- GitHub: implementation commit/branch/PR, push result, CI URL/status; or not pushed and why.
- Build/install/release: version, artifact checksum/URL, signing/notarization, installed version; or unchanged/not performed.
- Unresolved issues, failed attempts and limitations:
- Next exact steps / owner input required:
```

Add the initial entry before substantial work, fill it out before ending the task, and update `Current resume state`. For another prompt or meaningful fix, append another entry. Preserve completed history; append any correction. If interrupted, leave a checkpoint with the working tree and running-job state when possible. A prompt that only yields advice still gets a short `NO CHANGE` entry.

## Prior work through 0.3.7 — consolidated history

Status: completed implementation/release work with explicit open acceptance gates. The stage-by-stage requests, examples, outcomes and commits are recorded in [CLAUDE-HANDOFF.md](CLAUDE-HANDOFF.md#conversation-and-implementation-history); detailed release evidence is in [VALIDATION.md](VALIDATION.md). This consolidation replaces neither git history nor the original conversation.

- Built and distributed the native background/login/menu app; added native settings, automatic/approval modes, per-app pauses, ignored words, custom phrases, US-English writing rules, abbreviations, product casing, sentence capitalization, conservative joined-word/context repairs, optional underlines, undo and manual rewrite protection.
- Investigated the ChatGPT disappearing-word report and changed edit transport/safeguards; added Claude/Electron accessibility preparation. User confirmed one physical Claude test on 0.2.3; current broad compatibility is unverified.
- Added licensed technical/name data, deeper contraction and missing/doubled-letter policies, rich typography, bounded attributed-text AX fallback, and native-ranked fallback for missing automatic recommendations across OS versions. Kept dictionary/transport concerns separate and retained structured-token/secure-field guards.
- Created the labeled illustrated Higgsfield demo and simplified GitHub/Homebrew installation. LinkedIn posting remains forbidden; browser draft state is not established here.
- Diagnosed the friend's screenshot as unnotarized distribution; implemented fail-closed stable-release preparation and notarization script, but successful Apple submission/stapling is blocked on setup and untested.
- Published 0.3.7 from `3ce0cc6`; final runtime commit `e53074a`. Exact ZIP SHA-256: `c4aca31312137dcc3f549d344968277c8d6aa097b8040e8263d0efa717df25ff`. Locally installed using the existing development signing identity; public archive is ad-hoc/unnotarized.
- Evidence: 154 tests passed locally and hosted macOS 14; universal build passed. UI automation did not establish a physical keyboard path. Instantaneous resource samples and name-index microbenchmarks are not sustained app measurements.
- Remaining: independent accuracy/false-correction evaluation, real-input compatibility and undo/stress matrix, sustained performance/power testing, signed/notarized first launch and reliable update validation. Do not relabel the current preview 1.0 without closing these gates.

## 2026-09-30 — Codex — Claude handoff and continuity protocol

- **Status:** COMPLETE — documentation prepared; commit/push belongs to this entry's accompanying documentation commit. Check `git log` and the remote for the final hash.
- **Request:** Give Claude full project context and instructions to improve spelling, accuracy, smoothness, speed and compatibility; tell it to update GitHub and log every task for return to Codex.
- **Starting state:** `main`, `3ce0cc69e375782e057e7e0d59338bf4b37414eb`, clean working tree. No existing root `CLAUDE.md` or handoff/work-log file.
- **Findings:** Current README/release/validation agree on 0.3.7; source CI is green. Both permissions, supported layout, keyboard-listener availability and login service are enabled. Native dictionary tests do not prove end-to-end editing. Historical real-input failures/limits are retained rather than overwritten by green tests.
- **Changed files:** `CLAUDE.md`, `docs/CLAUDE-HANDOFF.md`, `docs/WORK-LOG.md`. Added startup instructions, per-prompt logging protocol, project/commit history, baseline, source map, safety invariants, prioritized quality work, real-input/accuracy/performance expectations, GitHub/build/install/release steps and social-posting boundary.
- **Verification:** Read current repository scripts/docs/history; inspected live release and source CI; ran installed `--diagnostics`. Documentation links and whitespace checked before commit. No runtime tests rerun because no runtime/build logic changed; 154-test result is the recorded previous baseline, not a new test run.
- **Build/install/release:** Unchanged; no new release or application installation for these documentation edits.
- **Limitations:** This is a structured history, not a verbatim transcript. Current LinkedIn draft state and new physical-keyboard behavior were not inspected. No Claude task was launched automatically.
- **Next:** Open this repository in Claude and tell it to read `CLAUDE.md`; Claude should append its first scoped work entry and proceed with independent audit and measured fixes. On return, Codex reads the latest resume state, entries and actual git state before changing anything.
