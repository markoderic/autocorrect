# AutoCorrect first implementation batch

**Run only when Marko chooses to start implementation.** Prepared October 2, 2026 (America/New_York). Saving, reading or preparing this document is not authorization to execute it. Marko can start a fresh implementation session in this repository and paste the prompt below when ready. It is suitable for either implementation model.

---

Implement the first focused AutoCorrect improvement batch in `/Users/markoderic/Documents/Projects/autocorrect`: immediate first-character capitalization at verified new prose-field start, safe short-contraction repairs, and capitalized-misspelling detection so capitalization does not hide spelling errors.

I am choosing to start this batch by submitting this prompt. Authorize local source/test/documentation changes, relevant tests and local builds for validation. Keep this batch local and reviewable: do not commit, push, publish, bump release metadata or replace `/Applications/AutoCorrect.app`. You may use a disposable local build for editor validation without resetting settings or permissions; avoid running two correction listeners together, and restore the original running-app state afterward. If the available environment prevents a check, record the limitation and the exact small manual check needed rather than claiming it passed. Do not launch another chat, delegate to other sessions or send messages elsewhere.

## Read before editing

Read `CLAUDE.md`, `docs/CLAUDE-HANDOFF.md`, `docs/NEXT-CHAT-HANDOFF.md`, the Current resume state and latest entries of `docs/WORK-LOG.md`, and the relevant acceptance requirements in `docs/VALIDATION.md`. Inspect current Git status/history and applicable repository instructions. This explicitly activated prompt authorizes only the batch below; it supersedes the handoff's planning-only restriction for this batch and older instructions to install/push/release. Preserve all existing local edits, untracked planning documents, preferences, dictionaries and user data. Never reset or clean the checkout to obtain a baseline.

Recorded baseline as of October 2: local `main` HEAD `5e74bc3`, latest runtime commit `0c26c53`, installed 0.3.9, remote main `fa295b7`, latest public release v0.3.7. Local 0.3.8/0.3.9 are unpublished; README/cask reference unpublished 0.3.9 assets. These are historical observations: verify the local source and installed version read-only and distinguish them from public status, which may remain last-known if not rechecked. Prior push denials are not permission to retry or find another route. Reported 194 tests with one gated skip belong to earlier runs; do not present them as your result. The reported 86.7% is one-corpus correction coverage, not overall app accuracy or untouched held-out evidence.

Append an IN PROGRESS entry to `docs/WORK-LOG.md` before substantial implementation, including starting commit, existing changes and scope. Review actual source and reproduce the relevant gaps with targeted fixtures before choosing changes. Likely starting points: `Sources/AutoCorrectCore/SentenceCapitalization.swift`, `EnglishWritingRules.swift`, `SpellingScan.swift`, `NameLexicon.swift`; `Sources/AutoCorrect/CorrectionEngine.swift`, `KeyboardMonitor.swift`, `AccessibilityText.swift`, preferences/settings and existing edit/undo helpers. Read call sites and relevant tests; the handoff's source line numbers may have shifted.

## 1. Immediate capitalization in a new prose field

- Extend the existing sentence-capitalization preference; preserve explicitly saved on/off choices and default it on for fresh installations. Use a clear label such as “Capitalize sentence starts.” Setting Off must disable the new behavior as well as the existing feature it controls.
- Capitalize the first alphabetic character as it is typed at verified field start, before the rest of the word or a space is required. Support leading spaces and opening quotes/brackets where field-start and caret evidence is reliable. A lowercase `h` typed alone in an eligible empty field should become `H` before the next character is typed.
- Require actual focus, caret/selection and field-start evidence. Offset zero of a bounded text snapshot is not proof of document start. Do not capitalize a mid-document word just because the field gained focus or earlier text is outside the snapshot. When evidence is unavailable, abstain and explain the limitation.
- Preserve existing `. ? !` capitalization behavior and timing. Do not expand this batch into new immediate paragraph-start, paste or emoji-prefix behavior. Add explicit regression expectations for those cases; retain existing supported behavior and otherwise abstain.
- Preserve canonical completed-token casing such as `iPhone` and `eBay`, exact custom replacements and ignored vocabulary. Reconcile the initially capitalized letter with the recognized completed token without correction loops. A deliberate lowercase rewrite wins for that occurrence; it must not create a global dictionary entry.
- Preserve IME/composition, dead keys, Unicode, selections, secure fields, excluded apps, code, paths and URLs. Do not blindly rewrite key events, guess a caret, change host settings, or synthesize Return in a composer where it might submit.

## 2. Safe short-contraction repair

- Improve the bounded class of damaged short contractions, including leading transpositions and apostrophe-normalized forms. Do not hard-code only `odnt`, remove all short-word/prefix safeguards globally, or compensate by broadly lowering correction confidence.
- Required prose fixtures include `I odnt know → I don't know`, field-start `odnt do that → Don't do that` with capitalization enabled, `I dont know → I don't know`, `Odnt do that → Don't do that`, and `ODNT DO THAT → DON'T DO THAT`. Preserve lowercase when field-start capitalization is off and input is lowercase. Test straight and smart apostrophes and retain existing `doenst`/damaged-contraction coverage.
- These fixture results must arise from defensible candidate/context evidence. Ambiguous isolated tokens may abstain; record the distinction from the required prose examples. Do not reinterpret literal spaced letters `O D N T` as the token `odnt`.
- Include valid-word competitors and negative cases: `font`, `dent`, `donut`, names/custom vocabulary, identifiers, URLs and explicit manual overrides. Unknown names must not be forcibly converted into contractions. An incorrect automatic change is more serious than a miss.

## 3. Capitalized misspellings remain detectable

- Remove or narrow the blanket capitalized-word exclusion that would hide a remaining typo after immediate capitalization. Sentence-initial misspellings should remain eligible for spelling detection and existing indication.
- Separate spelling detection from automatic replacement and geometry/rendering. Capitalization is neither proof of correctness nor permission to replace a name. Preserve recognized legitimate names, acronyms, explicit ignored words and custom casing; do not expand the name lexicon wholesale.
- Use the existing persistent spelling-indicator path. Do not rewrite the overlay or claim every editor supports underlines. The recorded Codex composer (`com.openai.codex`, previously displayed as ChatGPT.app) exposed no word rectangles: a detected count is not a rendered underline, nor evidence about a separate ChatGPT app.

## Verification and acceptance

Keep the changes small and separately reviewable: capitalization/event delivery, contraction policy, and the necessary scan adjustment. Use existing edit transport and undo protections unless a scoped, demonstrated reason requires a change. Keep processing offline, bounded and low-power; no cloud models, added large engines, typing logs or private-data scanning.

1. Establish before/after results for the targeted fixtures. Add meaningful positive and negative regressions for the behaviors above, including capitalization Off, saved preference preservation, field-start evidence, rapid next characters, deliberate lowercase rewrites, canonical casing and capitalized-typo detection.
2. Verify text preservation during continued typing, following text and selection preservation, focus/caret changes, Unicode/IME boundaries, undo after further typing, and manual rejection without repeated correction. Do not reintroduce unsafe selected-text writes or retry a deletion that has already been posted.
3. Run relevant tests, the full existing suite, and the repository's required local build checks for the changed code. Report exact pass/fail/skip counts, OS and commands. If a native dictionary test differs by OS, report it honestly instead of weakening its assertion without evidence. Do not run a large tuning campaign or invent a new headline accuracy target.
4. Validate in disposable fields in TextEdit, Claude desktop and Codex, plus a browser prose field if available. Never send a message or modify a real user document. Record app identity/version, field type, host correction setting as observed, physical versus injected input and actual resulting text. For immediate capitalization, demonstrate the first letter changing before a delimiter. Physical typing and a demonstrably equivalent event path are different evidence; automation that bypasses the listener is not a pass. Missing geometry does not by itself prevent checking correction delivery.
5. Compare the changed path's typing responsiveness and resource use to baseline with a bounded check. Identify any extra per-keystroke AX work or redundant scans. No sustained battery-life claim from a short measurement. If a before-build comparison cannot be obtained without disturbing current work, report the gap.

Finish `docs/WORK-LOG.md` and update Current resume state with changed files, behavior, actual evidence, failures/limitations, regressions, local source versus installed/public versions, and exact next steps. Keep prior entries intact. Record no install, commit, push or release. Leave the scoped diff ready for independent review in the existing Codex planning chat; do not contact that chat yourself.

## Explicitly outside this batch

Do not implement grammar/missing-punctuation analysis, its three-way settings or interactive suggestion UI; broad name expansion; cross-editor overlay redesign; native Apple underline suppression; a new architecture; distribution/notarization; marketing; or release work.

Retain the later-stage plan: red wavy spelling marks; subtle amber dotted grammar/missing-punctuation phrase marks with a non-color distinction and accessible label; deliberate hover/click explanation with Apply/Dismiss; no unsolicited pop-ups or focus/click interference; unchanged dismissed suggestions stay dismissed. Interactive suggestions require a separate feasibility design because the current overlay is click-through. Grammar remains independent with Automatic / Indicate only / Off. Automatic applies clear validated repairs and quietly indicates uncertainty, Indicate never edits, and Off disables grammar work. Missing commas, missing periods and broader grammar remain planned; enough sentence context is required, and a pause alone must never insert a period.

In your final report, lead with what improved and any unresolved behavior. Include a compact acceptance table, distinguish tests from real-editor evidence, link the updated work log, and stop for review at the end of this batch.
