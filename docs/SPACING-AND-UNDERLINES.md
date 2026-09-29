# Missing spaces, apostrophes, and underline compatibility

Research and implementation, September 29, 2026.

## Corrections

The native `NSSpellChecker` on the development Mac accepted `pleas` as a correctly spelled plural noun, suggested `know` for `iknow`, and suggested `don'ts` for `doen'st`. Our existing contraction rules already repaired the straight-apostrophe example. The shared edit plan, however, rejected smart apostrophes entirely. That meant a valid correction could be proposed but never applied after an editor changed `'` to `’`.

The edit plan now permits the single-code-unit smart apostrophes U+2018/U+2019 in the deleted/reinserted span. Other non-ASCII deletions, combining marks, emoji, navigation, focus mismatches, and stale snapshots retain their guards. Misplaced apostrophes with otherwise exact contraction letters also qualify for contraction normalization. This establishes the edit-plan fix, not proof of which host behavior caused every reported miss.

Joined-word handling runs only after native misspelling detection and recognized-name/user-override checks. A pronoun-plus-verb rule preserves `I` in combinations such as `iknow` and `ithink`. Other two-word candidates must preserve every letter, agree with the native automatic recommendation, occur in its first five guesses, contain valid dictionary components, and begin with a prose function word or greeting. Each input is capped at 32 ASCII letters. This supports a productive family of combinations without an unbounded dictionary search or network request. Valid compounds and uncertain splits are not forced apart. The setting controls automatic acceptance; uncertain suggestions still use review.

`pleas` becomes `please` only at a clause start before an imperative/request verb, after that word completes. This is a narrow context heuristic. It does not claim full semantic understanding or cover every grammatical construction.

## Underlines and native macOS controls

Apple documents [`NSTextView.isContinuousSpellCheckingEnabled`](https://developer.apple.com/documentation/appkit/nstextview/iscontinuousspellcheckingenabled) as a text-view property. The setting belongs to that editor, not to every process on the Mac.

[WebKit's implementation](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/mac/TextCheckerMac.mm) separately tracks continuous spelling, grammar, and automatic correction. It reads `WebContinuousSpellCheckingEnabled` from the app's standard defaults and caches `NSAllowContinuousSpellChecking` the first time it checks that policy. Writing a global defaults key therefore cannot promise immediate disabling/restoring in running apps, and Chromium/custom editors may use different controls entirely. Automatically navigating other apps' spelling menus would also lack a reliable cross-app restoration contract after a crash or exit.

**No external preference is changed by AutoCorrect 0.3.4.** In particular, a user's already-disabled setting is not forced back on at exit. A universal “off while running/on after quitting” switch is not implemented because no reliable supported mechanism was established. Turning off native autocorrection is distinct from turning off native spelling underlines.

AutoCorrect's own overlay is independent of the editor's native spelling setting. Previously it required both whole-word and individual endpoint rectangles. It now accepts valid endpoints alone, or a word rectangle with matching AX line indices when endpoints are unavailable. All branches still check focus/text identity, screen bounds, finite geometry, and single-line placement. No position data means no overlay. Underlines mark only the latest completed possible misspelling, clear on input/navigation, and expire after five seconds; they are not a persistent document-wide spelling layer.

## Evidence limits

Regression tests use the actual native checker for reported spelling and joined-word examples, plus deterministic edit-plan, undo, contextual negative, settings, and AX-geometry fixtures. They do not establish physical-keyboard delivery or underline rendering in every app. See [validation](VALIDATION.md) for release checks.
