# AutoCorrect 0.3.16: missing letters, keyboard proximity and quick controls

Measured October 14, 2026 on Apple silicon, macOS 27.0.1 (26A434). This is a preview toward 1.0, not an overall English-accuracy claim.

## What changed

- Completed phrase context can repair a missing letter in `with`, `wants` and `menu`, including `I agree wit that`, `the user wats to type` and `the men bar`. These are bounded omission checks plus grammatical frames, not unconditional replacements of valid `wit` or `men`.
- Nearby QWERTY keys contribute to a bounded candidate score, together with Apple's dictionary recommendation and separation from competing guesses. It handles certain more damaged spellings, including `ecaple`. A narrow plural frame also distinguishes `spelling mistaked` from singular/verb alternatives. Other layouts do not use QWERTY distances.
- Added indefinite-pronoun possessives, context for inserted letters in `this`, and conservative invitation/contraction improvements. Lowercase `os` becomes `so` in eligible prose; `OS`, `import os`, and `os.path` remain intact.
- Replaced the primary long menu with a native quick-controls panel: status, pause/resume, correction mode, per-app controls, settings and recent actions. Full controls remain available through More controls/right-click. Settings checkboxes now stay synchronized with menu changes.

## Paired measurements

| Measurement | 0.3.15 | 0.3.16 |
| --- | ---: | ---: |
| Authored positive phrases repaired | 18/40 | 39/40 |
| Authored valid-text controls preserved | 50/50 | 50/50 |
| Broad spelling: exact repairs, isolated | 3,405/4,097 | 3,407/4,097 |
| Broad spelling: missed, isolated | 581 | 579 |
| Broad spelling: wrong replacements, isolated | 96 | 96 |
| Broad spelling: exact repairs after `please check` | 3,328 | 3,330 |
| Broad spelling: wrong replacements after `please check` | 88 | 88 |
| Existing valid-word corpus entries changed | 12/2,928 | 12/2,928 |

The 90 focused cases exercise the owner's examples and related positives/negatives through the production preview path. The remaining positive miss, `now its just working`, is deliberately left ambiguous: the phrase can continue with `parts`. Completed article context such as `its a problem` is supported. Valid-text controls include ordinary wit/men, possessive its, uppercase OS, identifiers, names, regional spelling and legitimate double letters.

The broad corpus is Wikipedia common misspellings revision 1199637275, with 4,097 single-target errors plus 207 ambiguous entries, evaluated in two contexts, and 2,928 controls: 11,536 assessments. Case-only and regional matches are tracked separately. Some changed controls are regional/case differences or questionable entries, but harmful rare-vocabulary substitutions remain. This corpus and the focused fixtures have been inspected during tuning; neither is fresh independent held-out evidence, despite legacy headings in the raw report.

Native dictionary results varied between runs. An initial old-build run had 3,406 exact/95 wrong. Re-running untouched 0.3.15 from commit `783c646` reproduced the later native outputs; the table uses that recheck. The final policy adds `ciriculum` → `curriculum` and `exchanching` → `exchanging` on this broad set. An earlier aggressive one-edit proximity trial raised wrong replacements to 122 and was rejected. More corrections alone was not accepted as improvement.

Raw local evidence is under `evaluation/results/2026-10-14-accuracy-ui/`: `baseline.json`, `after.json`, `spelling-before-recheck.{json,md}`, `spelling-after.{json,md}`, and the rejected trial. These unrelated evaluation assets remain local; the focused capture test is committed and can be rerun with `TYPING_AUDIT_OUTPUT=/tmp/typing-audit.json swift test --build-system native --filter TypingAccuracyAuditTests`.

## Resource cost and validation

- No network service, model download, web view, polling timer, or typing history was added. Context stays capped at 256 UTF-16 units; edit scoring caps word length at 32 and considers at most five native alternatives. The panel is built on demand and its event monitors are removed on close. The status icon is cached.
- Focused preview median/p95: 0.610/13.137 ms before, 0.504/12.471 ms after. These are short, single-host calls, not physical keystroke latency or statistically established speedups.
- A 20-second installed-process sample after the changes reported median 0.0% CPU, mean 0.135%, maximum 2.6%, and maximum RSS 126.6 MiB. The earlier build's short sample had 0.0% CPU and 139 MiB RSS. Process lifetimes and UI states differ; this does not prove lower memory, battery impact or sustained typing performance. Model/service memory outside this process is not included.
- Final local suite: 376 executed, 372 passed, four opt-in audits skipped, zero failures. The focused audit was also explicitly run: 39/40 positives and 50/50 controls. Added slow/fast engine sequences, following-text preservation, user overrides, manual retyping and layout/scoring controls. The build without FoundationModels passed; universal release compilation passed.
- **Owner-confirmed physical TextEdit result:** typing `I agree wit that ` became `I agree with that `. This is one real typing case, not broad editor compatibility. Earlier automated editor input did not establish the physical input path and is not counted as a pass.
- Quick panel appearance, accessibility labels, initial keyboard focus and pause/resume were inspected. Automated Tab/full-menu interaction did not establish a complete keyboard navigation pass; physical keyboard/accessibility acceptance remains open. The existing settings and standard menu remain available.

## Release and remaining work

Installed 0.3.16 retains the existing Apple Development identity and permissions. Public distribution uses a separate Developer ID signed universal archive. Apple accepted submission `fc778dde-f7cf-498b-b14e-b5d55f661b71`; the ticket and final extracted archive pass validation and Gatekeeper. ZIP SHA-256: `0ed68a6a8f0a335d7ee979c1c6ec2c64733015b80f3ef30d864892763d073d9b`.

Next: fresh independent conversational cases; rare-word protection; broader grammar/punctuation; physical fast typing, Undo and focus changes across editors; full keyboard navigation of the panel; sustained resource measurements; Intel runtime and another-Mac download/first launch. Intermittent doubled characters remain unisolated: no blanket duplicate-letter suppression was added. These gaps keep the release at preview status.
