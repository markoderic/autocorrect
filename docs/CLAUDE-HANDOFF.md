# AutoCorrect handoff for Claude

Prepared September 30, 2026, for Marko. This is a structured record of the available conversation and verified repository history, **not a verbatim chat export**. It preserves the requests, decisions, fixes, failed approaches, and unfinished work needed to continue. Read alongside [WORK-LOG.md](WORK-LOG.md) and [VALIDATION.md](VALIDATION.md); older validation sections describe their own releases, not the current release.

## Your assignment

Give this project an independent engineering review, then improve the actual app. Marko wants everyday spelling and text correction to be substantially more accurate, smooth, fast, and dependable, including desktop apps such as ChatGPT and Claude. Work toward an evidence-backed 1.0, not just a version bump. He prefers execution over repeated planning or unnecessary permission questions. Use his concrete examples as regressions, but fix the underlying classes of failures.

After each prompt, fix, or investigation, log your work under the root `CLAUDE.md` protocol so Codex can resume exactly where you leave off. Keep GitHub updated. Explain limitations plainly and distinguish planned, implemented, tested, installed, and released work.

## Verified starting state

| Item | State at handoff |
| --- | --- |
| Local repository | `/Users/markoderic/Documents/Projects/autocorrect` |
| GitHub | https://github.com/markoderic/autocorrect |
| Starting branch / source commit | `main`, `3ce0cc69e375782e057e7e0d59338bf4b37414eb`; clean before these handoff files |
| Installed / public version | 0.3.7; `/Applications/AutoCorrect.app`; [public prerelease](https://github.com/markoderic/autocorrect/releases/tag/v0.3.7) |
| Tests | 154 passed locally on macOS 26.6 during the preceding work; 154 passed in hosted macOS 14 CI |
| Latest source CI | [36633237549](https://github.com/markoderic/autocorrect/actions/runs/36633237549), success for `3ce0cc6`, rechecked September 30 |
| Runtime CI | [36632738855](https://github.com/markoderic/autocorrect/actions/runs/36632738855), success for `e53074a` |
| Live installed diagnostics | Rechecked September 30: Accessibility true, Input Monitoring true, listener available, layout supported, login service enabled |
| Package | Swift 5.9 package; macOS 13+; universal arm64/x86_64; native AppKit, no bundled browser or AI model |
| Published ZIP | 1,623,214 bytes; SHA-256 `c4aca31312137dcc3f549d344968277c8d6aa097b8040e8263d0efa717df25ff` |
| Signing | Public archive ad-hoc signed and unnotarized; local install uses an existing Apple Development identity |
| Important distinction | Enabled permissions and green CI do not prove correct physical-keyboard behavior in a host app |

Recheck current git state, installed version, signing identities, and CI before work; these are a dated baseline. Handoff/log documentation commits will follow the source hash above. Do not discard another agent's or the owner's changes.

## Product intent and non-negotiable behavior

- Native, small, low-power background Mac app, launch at login, menu bar control, and a compact native settings window. Initially the owner requested no main UI, then explicitly asked for a real settings UI and refined icon; both requests are reflected in the current design.
- English (US) by default. Automatic mode should apply supported corrections without asking for each one. Approval mode remains optional. Ambiguous guesses must not become destructive edits simply to avoid a prompt.
- User-defined phrase replacements and ignored words/names. Ignored words take priority; exact custom replacements retain their casing. Built-in expansions and product casing have toggles.
- Standalone `i → I`, contractions, sentence capitalization after `. ? !`, ordinary typos, missing/doubled letters, product names/acronyms, and clear missing spaces. Contextual `its/it's` and `lets/let's` require surrounding words; do not globally rewrite valid words.
- Reliable undo after continued typing. When a user manually changes an autocorrection back, stop correcting that occurrence repeatedly. Do not silently make that local override a permanent global dictionary entry.
- Preserve following text, selection/caret integrity, focus changes, Unicode boundaries, filenames, URLs, code, and passwords. Text loss is more serious than a missed correction.
- Broad app compatibility is the goal, not a guarantee the implementation can honestly make. Secure fields, IME composition, restricted/custom controls, terminals, and remote desktops may be unsupported. Do not bypass protections to advertise support everywhere.
- Keep text processing local. No recorded typing history, uploaded messages, contact/file scanning, or network model calls. Any new architecture must fit the small/offline/resource goals or be presented as a concrete tradeoff first.

## Conversation and implementation history

The following covers the substantive requests in this chat. Commit references and release validation are implementation evidence; user feedback is labeled separately.

| Stage / request | Result and remaining boundary |
| --- | --- |
| Initial native Grammarly-like utility; automatic correction on space; tiny, low RAM/power, background/login, GitHub/Homebrew | `521047b` initial app; `6deca2c` packaging follow-up. Event-driven native Swift app and project-maintained Homebrew cask. No long-duration power claim. |
| Ignored names, custom words, red spelling underline, simpler icon/settings, US English, clarify paused apps and permissions | `dbf3d83`. Ignored Words/Text Replacements and optional overlay; both Accessibility and Input Monitoring are needed. Pause via the active app's menu item or Apps settings. Coding apps/terminals/password managers start excluded. Dictionaries are not every English word/name. |
| `teh` worked but `ths` missed; next keystroke erased corrected word inside ChatGPT desktop composer | `92a475f` broadened short-typo coverage and replaced unsafe selected-text writes with guarded keyboard edits. The exact current ChatGPT composer still requires physical-keyboard regression validation; do not infer a full fix from commit title or unit tests. |
| `i`, `im`, `ti`, `doesnt` missed; why 0.2.1 and when 1.0? | `6f63e20` explicit English writing rules. Preview version means unfinished acceptance gates, not a paid tier or a percentage. |
| Claude desktop did not correct; optional capitalization after period | `1e83ce7`, 0.2.3. Detect actual Electron framework and request accessibility with bounded retry. **User reported** that typing `teh ` then `next` became `the next` and both words stayed. This report belongs to that version and test only. |
| Broader everyday coverage, `its/it's`, abbreviations like `idk`, iPhone/UI, missing letters, dependable undo, real UI | `96ee67c`, 0.3.0. Native settings window, expansions, bounded context rules, queue, continued-typing undo, safeguards. Semantic correction is still limited. |
| Repeated `homebrew → homebred` fight; smaller vertically centered icon; demo/LinkedIn draft | `d485384`, 0.3.1. Occurrence-level manual rewrite protection plus compound safeguard; refined menu icon; Higgsfield illustrated MP4/GIF/poster. No real-typing performance evidence from the illustration. |
| Casual/professional LinkedIn wording; two Homebrew commands; download button and simple install | `bec5484` README/install improvements. Media tracked in `docs/media/`; local launch draft under ignored `dist/launch/`. User later explicitly asked to fill LinkedIn but **never hit Post**. Current browser draft state is not verified by this handoff; nothing here authorizes posting. |
| `lets`, inconsistent `screenshot`, `har`, GitHub, `iphoen`, contextual `its` | `f1ef7e0`, `cbb7de3`, 0.3.2. More context and product typo rules; canonical casing survives sentence starts. `har` remains ambiguous/accepted natively; arbitrary intended-word inference is not implemented. |
| Thousands of company/software/file names, PowerPoint, badly damaged `doenst` | `55ea876`, 0.3.3. Pinned, licensed name/technical lexicon, stronger contraction/name/general typo gates, period/colon deferral to protect structured tokens. Common prose words such as apple/word/excel must not all become brands. |
| `doen'st`, `pleas`, underlines missed, ask to disable Apple's underlines while app runs, `iknow` missing space | `011f552`, 0.3.4. Curly apostrophe edit support, conservative joined-word separation, contextual `pleas help`, underline geometry fallback. Standalone valid `pleas` is retained. **Automatic system-wide native underline toggling was not implemented:** no verified reversible universal live switch. See SPACING-AND-UNDERLINES.md. |
| Capitalization after `? !`; automatic mode still asking | `cf91dd7`, 0.3.5. Toggle covers `. ? !`; capitalizes after the next word is completed. Weak guesses in automatic mode show an optional indication without a pending approval prompt. |
| `leets see`, `kiding`, pressure for stronger everyday accuracy and 1.0 | `a9a0324`, `ab48279`, `8f59551`, 0.3.6. Unique doubled-consonant repairs, context-gated damaged invitation phrases, ranked fallback when native automatic recommendation is absent. Preserve valid `riding`, `hoping`, etc. |
| Friend's first-launch screenshot; `speoll`; accuracy and compatibility everywhere | `50fa241` through `3ce0cc6`, 0.3.7. Screenshot was Gatekeeper's unnotarized-app warning, not a spellchecker error. Rich typography/attributed AX range support, ordinary-word casing fix, missing-native-recommendation fallback, larger corpus, strict notarization pipeline. Public warning remains until certificate/notary setup. |
| Current request: Claude input, fixes, GitHub updates, log every task for return to Codex | This handoff, root `CLAUDE.md`, and shared `WORK-LOG.md`. Documentation only in this task; no new runtime changes or new release. |

## Latest investigation: retain this evidence

0.3.7 added 78 hand-labeled misspellings in three contexts (234 assertions, part of the 154-test suite), plus negative cases and edit/reversal tests. `speoll → spell` already worked in the local engine before these changes: do not invent that it was the single discovered bug. Six new quoted/rich-space assertions failed before the typography fixes. `buisness → Business` exposed company lexicon interference with ordinary prose; that was repaired.

macOS 14 CI showed native `NSSpellChecker.correction(...)` returning nil for common words even while ranked guesses contained the correct spelling. Earlier attempts using trailing boundaries and fresh spell-document tags did **not alone** solve the issue. The final solution compares bounded sentence/isolated suggestions, permitting existing confident one-edit or unique letter-preserving repairs while respecting competing candidates and protections. Document tags are query-scoped and closed. Correlated native rankings are a heuristic, not independent votes or a calibrated probability.

The fix sequence is preserved in git: `912133c`, `815cd0d`, `cf9b81a`, `6ac7101`, `7234c3c`, `e53074a`. `6ac7101` had an intermediate compile error fixed by `7234c3c`; use the final baseline rather than cherry-picking a partial sequence. Final runtime and metadata CI passed. Do not hide or skip cross-version failures; collect fixed-fixture native evidence without logging user text.

A disposable TextEdit UI-automation attempt typed `speoll ` and `teh next` but did not produce correction; phase-only diagnostics showed no snapshot/edit activity for those injected keystrokes. This is **not a physical-keyboard pass**, nor proof that physical typing fails. No unrelated user document was modified. Normal tracing was turned off afterward. Prior automation had the same attribution problem. Do not keep repeating an automation method that bypasses the input path and call it a compatibility test.

## Implementation map

| Files / area | Responsibility |
| --- | --- |
| `Sources/AutoCorrect/CorrectionEngine.swift` | Native dictionary assessment, policy composition, correction delivery, pending checks, undo and rewrite state; start here for engine behavior |
| `AccessibilityText.swift` | Focus/caret snapshots, bounded plain/attributed range reads and small-field fallback, host access preparation, secure-field/focus checks |
| `KeyboardMonitor.swift`, `KeyboardEventSequence.swift` | Event tap, key/session tracking and constructed edits; input-path bugs differ from dictionary bugs |
| `Sources/AutoCorrectCore/CorrectionPolicy.swift` | Candidate confidence and native-ranked fallback policies |
| `EnglishWritingRules.swift`, `ContextualWritingRules.swift`, `SentenceCapitalization.swift`, `JoinedWordPolicy.swift` | Contractions/pronouns, limited phrase context, sentence starts, missing spaces |
| `NameLexicon.swift`, `BuiltInReplacements.swift`, `BundledLexicon.generated.swift`, `CompoundSpellingPolicy.swift` | Names, abbreviations/casing, generated vocabulary and compound protection |
| `CompletedWordBacklog.swift`, `KeyboardReplacementPlan.swift`, `TypingTypography.swift` | Bounded completed-prefix queue, fully prepared edits, permitted single-unit rich-text typography |
| `CorrectionUndoAnchor.swift`, `ManualRewriteProtection.swift`, `UserDictionary.swift` | Exact undo anchors, occurrence-level manual overrides, user dictionary precedence |
| `Sources/AutoCorrect/Preferences.swift`, `SettingsController.swift`, `AppDelegate.swift`, `AppIcon.swift` | Persistent preferences, native settings/menu/login lifecycle, icons |
| `SpellingIndicator.swift`, `UnderlineGeometry.swift` | Optional transient underline and geometry fallback |
| `RuntimeDiagnostics.swift`, `main.swift` | Fixed probes, permission diagnostics and phase-only opt-in tracing |
| `Tests/AutoCorrectCoreTests/`, `Tests/AutoCorrectTests/` | Deterministic policies/edit plans plus native dictionary/engine integration tests |

Unless a path is fully qualified, a core filename above lives in `Sources/AutoCorrectCore/` and an app filename in `Sources/AutoCorrect/`. Inspect actual call sites; this table is not a replacement for reading code.

Keep these invariants unless a tested design demonstrably improves them:

- At most 256 UTF-16 units before the caret, bounded AX value/range fallback, 256 cached assessments, no full-document polling.
- At most eight queued completed boundaries; navigation, focus, mouse, control-key and settings changes retire pending sessions. Stale reads may retry within bounds; a posted deletion must never be retried.
- Prepare the complete edit before deleting anything. Revalidate focus, real caret/selection and surrounding text. Do not reintroduce selected-text AX writes that leave text selected.
- Preserve following text exactly. Destructive backspaces/replay allow only ASCII and explicit supported single-unit smart quotes/spaces, not arbitrary graphemes, combining marks, invisible controls, or IME composition.
- Undo uses Control–Option–Command–Z or menu, lasts up to five minutes with bounded context/suffix (up to 96 supported characters). It does not hijack the host editor's Command–Z.
- Manual rewrite protection is local to an occurrence/context and bounded history (eight records), not a globally learned typo mapping.
- Underlines mark the latest completed possible misspelling only, depend on AX geometry, and clear on interaction/timeout. They are not continuous document-wide proofreading.

## Recommended first work, in order

1. **Independently audit and reproduce.** Read current engine/edit paths and tests. Classify failures: no key event, inaccessible/stale snapshot, dictionary acceptance, candidate policy, wrong edit, or verification failure. A dictionary tweak cannot fix missing events. Briefly log your findings and chosen first fix, then implement it.
2. **Create a held-out accuracy evaluation.** Separate tuning fixtures from evaluation. Include real-word errors, damaged apostrophes, insertions/deletions/transpositions/doubles, sentence boundaries, names/acronyms, compounds, merged words, and valid-word/structured-token controls. Use licensed or authored data with recorded provenance; include ambiguous cases whose correct decision is to abstain. Track false corrections, missed corrections, correct repairs and abstentions separately; do not report test pass rate as English accuracy. Compare baseline and changed behavior by OS/version. Do not claim statistical precision from a tiny handpicked corpus.
3. **Improve candidate selection systematically.** Preserve useful native ranking and local name recognition; inspect over-broad heuristics as well as missed repairs. Add positive and negative regressions for each behavioral change. For `its/it's`, `lets/let's`, `pleas/please`, and `har`, context matters. Avoid exhaustive ad hoc typo dictionaries and unmeasured aggressive thresholds.
4. **Validate real editor delivery.** Use disposable text in TextEdit, Notes/Mail, Claude desktop, ChatGPT desktop, Chrome and Safari (standard and rich fields). Record exact app/OS version, input method and host autocorrect setting. Test fast subsequent words, punctuation, Unicode prefixes, cursor moves, focus switches, undo, deliberate rewrites, paused apps, and approval mode. Use physical input or a demonstrably equivalent method; if unavailable, record BLOCKED/NOT TESTED and ask for targeted user checks while continuing independent work. Never type into a live message recipient or modify unrelated documents.
5. **Measure before optimizing.** Measure sustained idle and active-typing CPU, RSS, wakeups, latency distribution and event/AX timeout behavior. Separate startup/index cost, native checker cost and edit transport. The prior 0.0% CPU/~61 MiB snapshot and 0.0041 ms warm name-lookup microbenchmark are not app-level performance promises. Keep tests/benchmarks deterministic and text-free in normal runtime logs.
6. **Close distribution gates.** Finish signing/notarization when credentials are available, validate the actual quarantined download on another Mac, and document install/update/login behavior. Do not let this block unrelated accuracy work, and do not pretend the warning is fixed.

Suggested small shared matrix columns: date, version/commit, OS, app/version, field type, physical/injected input, host correction setting, exact synthetic fixture, expected/observed text, undo/rewrite result, PASS/FAIL/UNSUPPORTED/NOT TESTED, evidence. A claimed supported app must have an actual result, not a checkbox inferred from AX availability.

## Build, install, GitHub and release instructions

From the repository root, inspect before changes:

```sh
git status --short
git log -5 --oneline
swift test --build-system native
/Applications/AutoCorrect.app/Contents/MacOS/AutoCorrect --diagnostics
```

For meaningful runtime fixes, run the applicable regression tests and then the full suite, and build both architectures with `./scripts/build.sh`. CI runs macOS 14 tests and universal compilation in `.github/workflows/build.yml`. Native results can differ from the development Mac. A docs-only change does not require rebuilding/reinstalling the app.

Use `security find-identity -v -p codesigning` to find the existing local identity rather than inventing one. Local builds may use `SIGNING_IDENTITY='Apple Development: ...' VERSION=<next-version> ./scripts/build.sh`; preserve signing identity/preferences/permissions where possible. Quit the running app cleanly before `./scripts/install.sh --replace`; the installer keeps a timestamped backup. Confirm the installed version/diagnostics and normal startup; leave trace mode off. Record source, public archive and installed app separately because the public archive and local build can have different signatures.

For GitHub work:

1. Review the diff, keep changes scoped, update the work log and validation documentation with actual evidence, commit and push. Do not force-push, overwrite unrelated work, or commit build artifacts/credentials. If using a new branch, prefer `codex/<description>` to match project convention; record branch and PR URL. Existing baseline is `main`.
2. Inspect hosted CI for the pushed commit. Fix genuine failures; do not claim completion from a local green run while hosted checks fail. If work remains incomplete, log the exact state and preserve it safely.
3. Publish a new preview only when there are validated release-worthy runtime improvements; no release is needed for every prompt or documentation update. Use a new version instead of silently replacing 0.3.7. Synchronize build/release defaults, bundle/source version references as applicable, README links, cask version/checksum, release notes and validation. Search for existing version references first.
4. `RELEASE_CHANNEL=preview VERSION=<next-version> ./scripts/release.sh` creates an explicitly unnotarized preview. Stable preparation requires an actual Developer ID Application identity and `NOTARY_PROFILE`. Read [NOTARIZATION.md](NOTARIZATION.md) and the scripts before release.
5. Verify the **final** ZIP, checksum, extraction, both architectures and signature; for a notarized release also verify accepted submission, stapled ticket and Gatekeeper on the extracted archive. Update `Casks/autocorrect.rb` to that exact final checksum. Do not zip a subsequently re-signed local app over the public artifact by accident.
6. Upload the matching ZIP/checksum and meaningful notes to the matching GitHub `vVERSION` release; label previews accurately. Verify asset URLs/digests and cask consistency afterward. Record commit, CI run, version, release URL, signing/notarization status and local-install status in the work log. Never put credentials in source or chat.

The September 29 certificate inventory contained only Apple Development and no repo signing secrets. An earlier question asking whether to create Developer ID through Marko's account or import his existing certificate had no reply at this handoff. Recheck availability, but do not assume unanswered credential/account authorization. Do not disable Gatekeeper or remove quarantine from users' downloads. Cleaning metadata from this project's generated build staging is a different operation and is already scoped in the scripts.

## Reference files and social boundary

- [README](../README.md): user-facing behavior, limits, installation and two-command Homebrew instructions.
- [VALIDATION](VALIDATION.md): detailed release-by-release evidence and open 1.0 gates.
- [RESEARCH](RESEARCH.md), [NAMES-AND-ACCURACY](NAMES-AND-ACCURACY.md), [SPACING-AND-UNDERLINES](SPACING-AND-UNDERLINES.md): prior findings, alternatives and source links. Verify time-sensitive API claims when changing them.
- [lexicon-sources.json](lexicon-sources.json), `scripts/update-lexicon.py`, [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md): 6,231 recognition terms / 2,234 canonical entries from pinned MIT-licensed CSpell sources. These are not accuracy metrics or all company names. Regenerate through the script and preserve licenses/provenance.
- [Media README](media/README.md): existing Higgsfield illustrated demo, MP4/GIF/poster and source. It is not a real editor recording. The latest known local LinkedIn draft is under ignored `dist/launch/`; do not add private drafts to public source automatically. Do not post/send on LinkedIn.
- The friend's screenshot is a private attachment outside this repository; its relevant message was “Apple cannot check it for malicious software.” Do not commit the personal attachment or its private filesystem location.

## What to report back

Lead with what improved and why it matters. Report tests and real-input evidence separately, any regressions/tradeoffs, current install/release status, and what is still blocked. Link the latest work-log entry. Do not call this 1.0 until the documented gates have evidence, and do not promise every app/English word. When Codex returns, it should need only `CLAUDE.md`, this handoff, the latest work-log state and the actual git diff to continue safely.
