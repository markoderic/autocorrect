# Next Claude task: automatic correction with persistent spelling underlines

Read `CLAUDE.md`, `docs/CLAUDE-HANDOFF.md`, and the current `docs/WORK-LOG.md` first. Continue from your local 0.3.8 work, preserving existing changes. This prompt supersedes the previous next-task order: reliable spelling underlines are the owner's immediate priority, alongside automatic correction quality.

## Owner's request

Make AutoCorrect feel like Grammarly with automatic correction: fix confidently identified typos as I type, and visibly underline unresolved spelling mistakes so I can see them. Right now some wrong words receive no underline. I want this to work throughout my Mac, including ChatGPT, Claude, browsers and native apps. Keep the underline toggle. Improve the actual behavior and verify it; don't just describe a plan or change the version number.

## Confirmed starting limitations — investigate these paths

Codex inspected the source on September 30 after your 0.3.8 commits:

- `SpellingIndicator.swift` owns a single panel, hides the previous mark on every `show`, and dismisses after five seconds.
- `CorrectionEngine.swift` checks completed-word boundaries and hides the indicator during typing/reset/edit paths. It does not maintain a persistent collection of unresolved misspellings in the active editor.
- `SpellingIndicator.show` requires a matching snapshot and usable AX bounds/line geometry; it returns without drawing if these fail. Detection, range identity and geometry failures are different problems.
- Underline detection relies on the assessment marking the word misspelled. Native dictionary acceptance, name/compound policy, ignored words or manual rewrite suppression may prevent assessment/flagging; identify the actual reason for each reported miss.
- This is AutoCorrect's own overlay, independent of whether native macOS spelling underlines are enabled. Do not turn the native setting back on and present that as an AutoCorrect fix.

## Required behavior

1. **Automatic correction remains primary.** In automatic mode apply high-confidence repairs on supported word boundaries without approval clicks. Do not force ambiguous replacements merely to make the app appear more automatic. Preserve the optional approval mode.
2. **Separate detection, correction and rendering.** A recognized misspelling with no safe replacement must still be eligible for an underline. A geometry failure must not be reported as “spelling is correct.” Distinguish possible spelling errors from uncertain grammar/meaning; do not mark every unknown name or valid contextual word as definitely wrong.
3. **Persistent, multiple underlines.** Keep red wavy marks beneath unresolved misspellings in a bounded visible region of the focused editable field. Typing the next word or five seconds elapsing must not permanently erase earlier unresolved marks. Remove a mark when the word is corrected, ignored, deleted, or explicitly overridden. Briefly hiding stale geometry while recomputing is acceptable; orphaned or wrongly positioned marks are not.
4. **Existing text and edits.** Reassess a bounded visible region on field focus, paste and relevant edits, with debouncing and documented limits. Do not destructively autocorrect an entire existing document or pasted paragraph without a separate explicit user action; detecting/underlining existing errors is different from rewriting them. Preserve active-word behavior so partial words are not noisily flagged on every keystroke.
5. **Correct positioning and lifecycle.** Handle changes to ranges after edits, scrolling, wrapping, font/zoom changes, window movement/resizing, display changes, focus switches and app closure. Clip to the visible editor/window and hide when covered/inactive as appropriate. No floating marks over another app, offscreen text or secure fields. Overlay must not take focus, intercept typing, select text or block normal clicks.
6. **Reliable settings and overrides.** The underline toggle must clear/re-enable all marks predictably. Respect ignored words, paused apps, custom rules and deliberate manual rewrites. Preserve undo and host smart-punctuation handling. Do not reintroduce the endless correction/undo fight.
7. **Broad compatibility with honest status.** Implement supported native AX/text-marker/geometry approaches where evidence warrants them. Explicitly report when checking or geometry is unavailable rather than silently appearing operational. If an editor exposes text but no trustworthy coordinates, show a small useful status or count of unresolved errors without drawing guessed positions. If a separate integration is necessary, explain the concrete tradeoff and scope; don't claim every app works.
8. **Stay fast and private.** Use bounded text/range storage and bounded overlay count, invalidate/reuse data where appropriate, and debounce expensive work. Prefer supported change notifications plus bounded event-driven fallbacks over constant full-document scans. Measure the resulting idle/typing/scroll cost. No normal typing logs, remote text upload, screenshots/OCR as a continuous background workaround, or global changes to other apps' spelling settings.

## Implement and verify

- Start with a short source-grounded diagnosis identifying which misses are detection, policy, range tracking, or geometry failures. Reproduce at least one persistent-underline failure before changing it.
- Design a shared underline state/range model rather than patching only one app or one word. Read `AccessibilityText.swift`, `SpellingIndicator.swift`, `UnderlineGeometry.swift`, `CorrectionEngine.swift`, `TypingTypography.swift` and the existing edit/undo guards.
- Add meaningful tests for multiple errors, range shifts, typo-to-correct edits, ignored/manual overrides, toggle/pause, paste/focus, stale callbacks, wrapping/clipping and geometry loss. Include negative examples: valid uncommon words, technical names, structured tokens and secure/unsupported fields.
- Demonstrate in disposable text: two unresolved errors remain marked while a third word is typed; correcting one removes only its mark; scrolling/resizing repositions or safely hides and restores marks; switching apps removes the old overlay; turning the toggle off clears all marks. Include a detected misspelling with no trusted replacement and one safe automatically corrected typo. Choose verified fixtures from the actual engine, not assumed dictionary behavior.
- Test TextEdit, Notes, the actual ChatGPT and Codex app identities separately, Claude desktop, and Chrome/Safari standard and rich fields. Record app/version, field, input method, native spelling setting, expected/observed text and **rendered underline evidence**. Green geometry tests or a trace of successful correction alone do not establish that an underline appeared. Label untested apps accurately; never send a test message.
- For accuracy changes, report false replacements and misses separately. Your previous evaluation data was inspected during rule selection, so it should now be treated as development/regression evidence; reserve a new untouched evaluation set for a genuine independent check. Do not present an improvement on that corpus as overall English accuracy.
- Run the full suite and universal build, retain positive/negative regression protections, and measure CPU/memory/wakeups and interaction latency against the previous build under comparable conditions. Do not compare unlike footprint/RSS measures as a proven memory reduction.

## Finish the task and preserve continuity

Keep `docs/WORK-LOG.md` updated after every prompt/fix, including failed attempts, actual evidence and exact resume steps. Update README/validation to describe the final real behavior and limitations. Follow the existing GitHub/build/install/release instructions, preserving the distinction between local and public versions. Check the outstanding 0.3.8 push/release state first; do not publish broken download links or claim a release exists when it does not. If permission review blocks an operation, record the reason and remaining action without trying alternate routes to bypass it.

No new LinkedIn work. No claim of universal compatibility or a finished 1.0 without the documented acceptance evidence. Complete the implementable improvements and log any concrete blockers rather than silently dropping the underline requirement.
