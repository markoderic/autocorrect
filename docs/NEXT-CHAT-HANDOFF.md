# AutoCorrect: new-chat handoff and quality plan

Updated October 2, 2026 (America/New_York). Owner: Marko. Project: `/Users/markoderic/Documents/Projects/autocorrect`.

## Current authorization — October 3, 2026

The owner subsequently authorized implementation, the Codex repair/test pass, and now local installation plus GitHub source push. The planning-only restriction below is historical and superseded. Read the current resume state in `docs/WORK-LOG.md` for installed/source/CI status. Publishing a new release and LinkedIn posting are not part of this task.

## Historical starting scope — planning only

At the time of this planning document, the owner's instruction was **planning, not building**. This overrides older work-log instructions to code, install, push or publish next. Read this file and the latest entries in `docs/WORK-LOG.md`; consult `docs/CLAUDE-HANDOFF.md` for earlier history and `CLAUDE.md` for continuity rules. Do not implement app changes, change settings, rebuild, install, commit, push or release until a subsequent user instruction authorizes implementation. Read-only review and planning-document updates are in scope.

This fresh chat is the project's review/planning home. The owner expects to use Claude for several implementation runs, then return here for an independent review of what improved, what regressed and what to tackle next. Do not automatically create further chats or send messages to Claude. Preserve the current chat and the previous source/history.

## Latest user intent

- Make correction genuinely dependable in daily typing, including more complex misspellings and names, instead of describing the app as globally “87% accurate.”
- **Capitalize the first word immediately as typing begins in a new prose field**, with a toggle. Existing capitalization after `. ? !` is not enough. Distinguish first-character timing from correction only after a space.
- Example: user spelled out O D N T, intended `don't` (apostrophe between n and t). Primary fixture should be `odnt → don't`, including `I odnt know` and field-start `odnt … → Don't …`. Also inspect `Odnt` and `ODNT` with explicit casing policy; do not silently reinterpret literal spaced letters as the same input.
- Add grammar/punctuation assistance for missing commas, periods and other errors, with **Automatic / Indicate only / Off** choices. Owner favors automatic behavior, but wants the other modes available.
- Keep persistent spelling underlines and broad app compatibility in the plan. Do not conflate detecting a misspelling with safely correcting it or drawing an underline.
- Native, offline, small, low-power background utility. Preserve undo, ignored/custom words, manual rewrites and no text loss.

## Live baseline checked October 2

| Item | Current evidence |
| --- | --- |
| Local branch / HEAD | `main`, `5e74bc36d45afcb2194d0a72c30c4a4e225792f4`; clean before this planning task |
| Latest runtime commit | `0c26c53`: persistent underlines, 0.3.9 metadata; following `8d7733f` and `5e74bc3` are documentation |
| Installed version | 0.3.9, confirmed from `/Applications/AutoCorrect.app/Contents/Info.plist` |
| Remote main | `fa295b74123dd44ce13edfcf76f67d147fe7e547`, confirmed by `git ls-remote` |
| Latest public release | v0.3.7; no v0.3.8/v0.3.9 published, confirmed through GitHub |
| Reported local tests | Claude reports 194 tests, zero failures, one gated evaluation skip for 0.3.9; NOT rerun in this planning task |
| Hosted checks | Claude's local 0.3.8/0.3.9 changes have not been pushed or run in hosted CI |
| Distribution | Public previews unnotarized; previous Developer ID/notary setup blocker remains, not re-inventoried this turn |

Claude logged repeated session permission denials for push. Do not interpret those as a permanent GitHub permission diagnosis, and do not try another route around an active denial. Publication is outside this planning task. Local README/cask reference unpublished 0.3.9 assets, so publishing source and releases later must be coordinated. Do not run the old log's checksum command blindly: resolve relative ZIP paths from the checksum file's directory.

## What Claude actually changed

0.3.8 (`c7bd416`, `75522c3`, log `41a9708`): prefers some letter-preserving spelling repairs over wrong substitutions, blocks unrelated substitutions for joined phrases, expands safe splitting, adds twenty contractions, tightens damaged-contraction evidence, and preserves undo when the host changes straight punctuation into smart punctuation. Added a corpus evaluation harness. Known bad repairs remain, including `bedore → bedsore`, `lastr → laster`, `unwieldly → unwieldily`, and the lexicon collision `halp → Halp`.

0.3.9 (`0c26c53`): persistent multiword underlines with at most 32 tracked marks; bounded existing-text scans up to 2,048 UTF-16 units, AX observation, range updates and visibility clipping; status distinguishes detected words from missing geometry. It does not change spelling-correction rules from 0.3.8. The old claim that every underline disappears permanently after five seconds is now stale.

Claude reports persistent marks in TextEdit/Notes based on trace, on-screen panel geometry and rendered-pixel counts. Direct visual confirmation is still pending; the available capture method did not include the overlay. The Codex composer (`com.openai.codex`, displayed as ChatGPT.app in the log) exposes zero word rectangles: detected errors receive a count, not an AutoCorrect underline. Do not treat that as a separate `com.openai.chat` test. Claude desktop and browser underline checks remain untested in the log. Physical keyboard validation is also distinct from the logged event-path-equivalent automation.

The recorded 45-second active typing/scroll benchmark rose from 180 ms to 560 ms CPU between 0.3.8 and 0.3.9; about threefold in that workload, though absolute cost was small. This is not a sustained battery measurement or proof of poor idle behavior.

## Focused source review findings

This was a targeted static review of Claude's changes and the owner's symptoms, not a comprehensive code audit. No failing test, app interaction or dictionary probe was run this turn.

1. **Confirmed first-word capitalization gap.** `Sources/AutoCorrectCore/SentenceCapitalization.swift:8–15` requires a completed word/delimiter. `:62–77` requires preceding whitespace and sentence punctuation, rejecting actual field start. `CorrectionEngine.swift:474–478` uses that rule. Therefore the requested first-word/immediate behavior is absent by design; it is not simply an accuracy percentage issue.
2. **Confirmed damaged-short-contraction gap.** `Sources/AutoCorrectCore/EnglishWritingRules.swift:30–40` limits damaged input to 5–16 characters, contraction keys to at least five letters, and requires the first two letters to match. `odnt` is four letters, `dont` is a four-letter key, and the first two letters are transposed. That dedicated repair path cannot handle the example. Other native/generic paths could still produce it on some hosts; no end-to-end failure was reproduced here. Do not fix this by removing all length/prefix safety gates globally.
3. **Confirmed capitalized-word underline blind spot.** `Sources/AutoCorrectCore/SpellingScan.swift:59–61` allows only lowercase words, and `Tests/AutoCorrectCoreTests/SpellingScanTests.swift:19–23` reinforces the broad exclusion. Automatically capitalizing the first word without changing this scan policy can make its remaining typo disappear from existing-text marking. Name protection needs finer evidence than “has a capital.”
4. **Confirmed names have deliberate coverage limits.** `Sources/AutoCorrectCore/NameLexicon.swift:17–20` only recases fully lowercase input, and requires native misspelling or distinctive mixed-case canonical spelling. `CorrectionEngine.swift:503–509` lets recognized terms bypass general spelling repair. This prevents unwanted changes to names, but overbroad lexicon entries can conceal ordinary typos or assign brand casing. No specific missing personal name was supplied; gather examples before declaring which name rule is broken.
5. **Grammar is a narrow heuristic today.** `Sources/AutoCorrectCore/ContextualWritingRules.swift` targets forms of `lets`, `its/it's`, and `pleas`; it is not a general punctuation or grammar engine. The region scan in `CorrectionEngine.swift:340–350` requests spelling checks only. General missing-comma/period detection is new scope requiring measured language coverage and new safe edit behavior.
6. **Underline compatibility remains a rendering problem in some editors.** `SpellingIndicator.swift:27–49` rejects marks with no valid single-line bounds; wrapped words are not supported there. This should stay honest rather than guessing coordinates. The current placement loop performs several AX calls per mark on the main thread (`:70–77`): profile worst-case latency/cancellation before adding grammar marks or more scanning. The log also admits window occlusion is not computed.

Line numbers describe this baseline and may shift. These are the first review targets for the next build cycle, not completed fixes.

## Why “87% accurate” is misleading

The current `evaluation/latest-report.md` reports 1,776 exact repairs out of 2,048 single-target entries in its “held-out” isolated-word half: **86.71875% exact correction coverage on that dataset and host**. It also lists 1 case-only difference, 12 US-English variants, 182 misses, and 77 incorrect corrections. Do not combine categories without stating how they count.

That is not end-to-end app accuracy, nor the chance any correction is right. It does not measure the owner's distribution of typing, word-start capitalization, names in prose, rich-context grammar, event delivery, text loss, underline visibility, undo or latency. The corpus is encyclopedic misspellings; the second context is a fixed `please check` prefix. Valid-word controls are derived from the same corpus targets. Similar variants can fall on either side of the line-parity split. Moreover, Claude inspected both halves during rule selection; the former held-out half is now tuning/regression data, not an untouched independent evaluation. `docs/VALIDATION.md` already acknowledges this despite the older report headings.

Preserve these measured improvements as useful regression evidence. Replace the blanket percentage with a scorecard:

- Correct automatic repairs / eligible labeled errors (coverage).
- Correct automatic repairs / all applied repairs (precision), with US-English/case treatment stated.
- Incorrect changes / valid-word controls and per 1,000 representative typed words.
- Misses and abstentions, with their causes: detector, candidate generation, ranking/policy, field access, edit failure.
- Underline detection precision/recall and correct rendered placement separately, by editor.
- First-letter timing, actual edit latency, undo/manual-override behavior, resource use, and text-preservation stress results.

Create a newly labeled chat/email/document corpus with positive, ambiguous and already-correct examples. Group typo variants and source words before splitting to reduce leakage. Freeze a genuinely untouched evaluation set before tuning; after using a set to choose rules, retire it to regression status. Include different macOS versions and app versions. The owner's examples become regression fixtures, not new evidence of broad accuracy.

## Proposed next implementation batches — not authorized yet

### A. First-word capitalization plus short contraction repairs

**First-word setting:** propose “Capitalize sentence starts,” on by default, covering true field start and existing `. ? !` behavior; decide preference migration without resetting user choices. The requested experience is immediate first-letter capitalization in eligible prose, not waiting for a completed word. Establish a safe first-character event path with actual field-start/caret evidence; snapshot-window offset zero is not proof of document start. Do not intercept arbitrary keys blindly or invent a caret.

Keep canonical `iPhone`/`eBay` casing when the completed token becomes identifiable; initial character handling and completed-token casing must reconcile without loops. Preserve explicit custom casing, ignored words, code/paths, IME and manual reversions. In a chat composer Return may submit; never synthesize Return to detect sentence completion. Blank-field typing, leading quote/bracket/space, a genuine paragraph start, mid-document focus, paste, emoji prefixes and rapid next characters need explicit rules/tests. Do not capitalize the first visible word merely because earlier text is outside the snapshot.

**Damaged contractions:** generate candidates using apostrophe-normalized forms, bounded edit operations and context; consider leading transpositions rather than requiring the same first two letters. Rank `odnt` against other candidates using native/context evidence, preserving valid words and names. Short words are highly ambiguous: add negative cases such as `font`, `dent`, `donut`, identifiers and deliberate `odnt` overrides alongside `I odnt know`, `odnt do that`, `dont`, `doenst`, smart apostrophes and uppercase variants. Add a general regression family, not one hard-coded `odnt` substitution. If evidence is uncertain, indicate rather than force a wrong correction.

**Exit criteria:** true field-start letters capitalize at the intended timing; missed capitalized spellings remain detectable; tested short-contraction cases improve without new valid-word changes; following text/undo/manual rewrite tests and real editor checks pass. Do not choose a headline accuracy target before measuring the baseline.

### B. Names, detection and persistent underlines

Separate recognition-only entries, canonical casing and authorized user vocabulary. Audit collision examples such as `halp` before expanding the name list. Add a maintained exclusion/ambiguity policy and test ordinary words that share brand names. Personal names should be explicitly added through user vocabulary; do not scan contacts, files or private messages automatically. Unknown capitalized words can be checked, but capitalization alone should neither prove correctness nor authorize replacement.

Improve capitalized/quoted/wrapped-word scan coverage and geometry diagnostics. Test actual Claude desktop, Chrome/Safari standard/rich fields, native editors and the Codex composer, documenting counts-only cases. Investigate supported range/line/text-marker or editor-integration paths; do not represent a count badge as an underline. Missing app geometry is not solved by a larger dictionary. Profile redundant scans/AX calls and avoid stale overlay positions/occlusion.

The earlier request to suppress native Apple underlines remains a separate feasibility item, not a precondition for accuracy. The log proposes global/per-app settings that include autocorrection controls; these must not be conflated with underlines. No universal reversible method is established. Do not silently change unrelated app preferences. Plan per-app coexistence first, and verify crash recovery before any proposed automatic suppression.

### C. Grammar and punctuation with three modes

Proposed controls (spelling remains independent):

| Mode | Behavior |
| --- | --- |
| Automatic | Apply only independently validated high-confidence grammar/punctuation fixes; indicate uncertain cases without forced rewrites. Honor undo/manual rejection. |
| Indicate only | Show a distinct grammar indication with explanation/proposed change; never modify text automatically. |
| Off | Disable grammar detection, its indicators and edits completely; spelling settings remain unchanged. |

Owner prefers Automatic; support a top-level mode and, if needed, separate punctuation/grammar controls. “Automatic” is not permission to rewrite tone, intent or every stylistic preference.

**Agreed quiet suggestion UX, relayed October 2:** spelling uses a red wavy underline. Grammar and missing-punctuation suggestions use a subtle amber dotted underline on the associated phrase. Pattern and accessible category labels distinguish the two without relying on color. A deliberate hover or click reveals a small explanation, for example “Add a comma after however,” with **Apply** and **Dismiss**. Provide an accessible way to reach these actions without relying on pointer hover alone. No unsolicited pop-ups, bouncing icons, repeated reminders, focus stealing or interference with ordinary editor clicks/selection. A dismissed suggestion stays dismissed while its relevant text is unchanged; unrelated edits must not resurrect it.

This interaction is a future requirement, not an existing capability. The current overlay is click-through; assess hover targeting, hit testing, accessible activation, focus behavior and dismissal state separately before choosing an implementation. A solution must preserve ordinary host-editor interactions, and unsupported geometry must not be replaced with guessed targets. Missing punctuation needs a phrase anchor even when the proposed edit inserts at a zero-length range. Revalidate context when Apply is chosen. Enough sentence context is required for both suggestions and automatic fixes; a pause alone never authorizes a period.

Start with offline bounded sentence analysis and a provider interface. Benchmark native grammar results and small explicit rules on labeled examples before deciding whether an additional local engine is worth its memory, startup, licensing and maintenance cost. Apple's [NSSpellChecker documentation](https://developer.apple.com/documentation/appkit/nsspellchecker) exposes grammar/unified/background checking; API availability is not evidence that it catches the requested errors well. [Grammar result details](https://developer.apple.com/documentation/foundation/nstextcheckingresult/grammarDetails) may support explanation; validate actual outputs on supported macOS versions. Do not add a cloud service or large bundled model under an assumed permission.

Design suggestions as bounded range edits with category, explanation, proposed replacement, evidence and original context. Cancel stale asynchronous results after typing/focus/selection changes; revalidate before applying and support undo after continued typing. Resolve overlaps between spelling, name casing and grammar to avoid double edits and cycles. Missing punctuation creates zero-length insertion ranges, which need explicit safe transport and an indication anchor; existing word replacement/underline code does not automatically cover them.

Evaluate punctuation separately from spelling. A pause does not prove a sentence ended. Decide completion boundaries before auto-inserting a period, particularly in chat fragments, titles, lists, decimals, abbreviations and URLs. Commas can change meaning; ambiguous examples stay indicated. Suggested fixtures include `I bought apples bananas and oranges`, `if it rains we will stay home`, duplicated words, clear subject–verb agreement, missing final punctuation in complete prose, and correct informal fragments. Label acceptable punctuation variants instead of requiring one style everywhere.

**Exit criteria:** modes persist and behave independently; Off produces no grammar side effects; suggested and automatic edits have validated sentence-level evidence; deliberate hover/click and accessible activation work without stealing focus or interfering with the editor; unchanged dismissed suggestions stay dismissed; no completion/punctuation insertion races, text loss, repeated rejection or semantic rewriting; latency/resources measured with grammar on and off.

### D. Release readiness, after quality work is authorized

Reconcile local/public versions, review the accumulated changes, run hosted macOS checks after an authorized push, validate exact final artifacts, then publish accurate release notes/cask links. Complete Developer ID/notarization setup and actual first-launch testing separately. No release, force-push or permission workaround is authorized by this planning handoff. 1.0 requires the evidence in `docs/VALIDATION.md`, not a renamed preview or a single corpus score.

## October 2 follow-up: recommended next step

Marko asked this chat to develop the plan further. The following are recommendations, not authorization to implement or settled user decisions.

**Next Claude batch: field-start capitalization and short contractions.** Keep the existing correction and edit architecture. Deliver these as two separately reviewable changes within one focused batch, with the minimum capitalized-word scan change needed to avoid hiding a typo after its first letter is capitalized. Broader name-lexicon expansion, overlay compatibility work and grammar stay in later batches.

Recommended product decisions:

- Reuse the sentence-capitalization toggle, relabeling it if necessary. Preserve existing on/off preferences; recommend on for fresh installations. Immediate timing applies to the first alphabetic character of a verified empty prose field, including supported leading spaces/quotes/brackets. Existing punctuation-triggered capitalization remains at its current timing in this batch. New paragraphs, paste and emoji prefixes need explicit expected outcomes; defer new automatic behavior there until separately validated. Never infer field start from a truncated snapshot.
- A deliberate lowercase rewrite wins for that occurrence. Completed-token recognition must restore authorized canonical casing such as `iPhone`; immediate capitalization must not repeatedly fight it. Preserve custom replacements and ignored words.
- Repair a bounded family of damaged short contractions using candidate/context evidence. Required examples include `I odnt know → I don't know`, field-start `odnt do that → Don't do that`, `Odnt → Don't` and `ODNT → DON'T` in suitable context. These express intended casing; ambiguous isolated tokens may abstain. Preserve native apostrophe style where supported and test both straight and smart forms.
- Check capitalized sentence-start misspellings without assuming every capitalized unknown is a correct name or an authorized replacement. Keep recognition, indication and automatic replacement as separate decisions.

Batch acceptance is a small before/after table: first-character timing; contraction repairs and competing valid words; capitalized-typo detection; continued typing with no text loss; undo and deliberate rewrites; code/URL/custom-word protection. Require editor delivery evidence in TextEdit and Marko's main chat composers, identifying exact app identities and physical versus equivalent automated input. Report inaccessible fields and missing geometry honestly. No broad accuracy claim follows from these fixtures.

**Following batch: names and underline reliability.** Audit ordinary-word/name collisions first, then broaden capitalized/quoted/wrapped-word detection and validate persistent placement in native editors, Claude desktop, Codex and browser fields. Add user-supplied personal names through explicit vocabulary. Treat missing editor geometry as a compatibility investigation, not a spelling-rule fix. Check resource cost before increasing scan work.

**Then grammar and punctuation.** Recommend one independent three-way control initially: Automatic / Indicate only / Off, with Automatic as the proposed new-feature default only after its automatic rules meet acceptance criteria. Avoid separate grammar/punctuation sub-controls until real use establishes a need. Introduce detection and reviewable suggestions before enabling automatic edits for each validated error category. Start with narrow, demonstrable errors; ambiguous commas and missing final periods remain suggestions until there is a reliable sentence-completion policy. A typing pause alone is not that policy. Evaluate the existing native offline option first; choose an added engine only from measured coverage and resource tradeoffs.

**Review cycle:** authorize one batch, let the implementation model implement and record evidence, then return here for diff-based review before expanding scope. The first-batch prompt is prepared in [IMPLEMENTATION-PROMPT-BATCH-1.md](IMPLEMENTATION-PROMPT-BATCH-1.md), labeled **run only when Marko chooses to start implementation**. Saving or reading it does not activate it. No release work belongs to this planning step.

**Session recommendation:** use a fresh Claude implementation session for this small batch, pointed at the same repository and its handoffs; retain this Codex chat for independent review. A fresh session provides bounded context and a clean scope while preserving the earlier work through source/history and documents. This is a workflow recommendation, not evidence that Claude Fable 5.1 beats GPT-6 Astra. Astra is also a reasonable implementer; the prepared prompt is model-neutral. No model change, new session or message dispatch is implied or performed.

## Working agreement for the new chat

For each future Claude batch, require a work-log entry stating the user request, commit range, changed behavior, positive/negative tests, native/real-editor evidence, resource comparisons, regressions, installed version and public release status. On return here, review the actual diff and source alongside the log; do not accept claimed percentages or test passes as sufficient by themselves. Prioritize text loss/false corrections, then common misses, then broader grammar scope. Keep a small per-batch acceptance list rather than building everything at once.

Current review result: Claude made useful reliability and underline improvements, but the first-word behavior and short-contraction gap are real; names/uppercase detection and full-editor rendering still need work. Grammar/punctuation is an additional feature area, not a switch already hidden in settings. Continue planning until the owner explicitly asks to build.
