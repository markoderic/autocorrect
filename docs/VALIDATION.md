# 0.3.0 validation

Checked September 29, 2026 on Apple silicon, macOS 26.6, Swift 6.4.

- **93 tests passed, zero failures.** Includes 51 labeled deterministic spelling fixtures (27 positive, 24 negative), native-ranking disagreement regressions, phrase validation/reversal, exact trailing-text preservation, bounded word-boundary backlog, context suggestions, exact UTF-16 undo anchors, and integration of engine preferences/overrides. This is regression coverage, not a measured English accuracy percentage or a physical-keyboard stress test.
- Final installed engine smoke checks: `i → I`, `im → I'm`, `doesnt → doesn't`, `ti → it`, `ths → this`, `idk → I don't know`, `iphone → iPhone`, `ui → UI`, `capitazed → capitalized`, `inconvient → inconvenient`, `acomodation → accommodation`, `probblity → probability`. Valid samples `ill`, `well`, `were`, `its`, `world`, `Marko`, `GitHub` remain unchanged. Native dictionary ranking can vary by context and macOS version.
- Native settings UI visually inspected. Preview visibly produced `I I don't know iPhone UI capitalized` for `i idk iphone ui capitazed`; `lets go` showed `let's go (approval required)`. These exercise the real engine in the app window, not editing in a different app.
- Added a temporary phrase through the UI, disabled expansions, restarted/replaced the app, and verified both persisted. The temporary phrase was then removed and expansions restored to on. English (US), context suggestions, sentence capitalization, and underlines are on. Existing user settings are otherwise preserved.
- A TextEdit automation check produced `i next` but **did not enter the keyboard listener**, as established by phase-only tracing. This does not count as an end-to-end pass or as evidence of physical-keyboard failure. Real-keyboard rapid typing, global undo delivery, and app-by-app validation remain required. The earlier user-confirmed Claude result below belongs to 0.2.3; do not infer current universal compatibility from it.
- Static review found and fixed stale AX read drops, lost undo records on canceled delivery, and verification callbacks crossing typing sessions. Reads retry at most three times; already-posted edits never retry deletions. Focus, mouse, navigation, control keys, and setting changes retire the session, while ordinary subsequent typing preserves queued boundaries. These safeguards still need real-editor stress testing.
- Universal arm64/x86_64 release compilation and strict signature verification passed. ZIP: 1,449,441 bytes. SHA-256 `6fcef8b93aaeb59dc0173ac8f35e9f6f6aa1b9230700ce9593c07ba27ef6f8b0`. Installed app allocation approximately 1.9 MiB, including the new native icon. Public build remains ad-hoc signed and not notarized.
- A short background-process snapshot after launch showed about 101 MiB RSS and 0.1% CPU. This is not a sustained active-typing or battery benchmark; opening Settings can change memory use.
- Installed Accessibility, Input Monitoring, keyboard listener, keyboard layout, and launch-at-login registration checks pass. Actual logout/login was not exercised. Final normal launch has phase tracing off.

## 1.0 gates still open

Use a disposable field in TextEdit, Chrome, Claude desktop, and the desktop chat composer. With host autocorrection disabled for attribution, physically type `i ths next`, `idk next`, and `capitazed next`; verify exact text and no selection. Reverse the last correction with Control–Option–Command–Z after typing the next word; repeat with phrase expansions, fast input, focus changes, and an emoji prefix. Check approval-only context changes and paused apps. Record actual app versions and pass/fail/unsupported results. Complete sustained active/idle resource measurement and signed/notarized distribution before declaring a stable 1.0.

---

# 0.2.3 validation

Checked September 29, 2026 on Apple silicon, macOS 26.6, Swift 6.4.

- All 59 tests passed, 0 failures. New tests cover period capitalization, abbreviations/initials/structured text, single-letter words, exact custom and ignored precedence, disabling capitalization while keeping spelling correction, preference persistence, Claude's actual framework name, bounded AXValue fallback with no character count, invalid/oversize ranges, and quoted-word replacement plans.
- Installed Settings UI shows “Capitalize after a period,” initially on. Turned it off, saved, relaunched, and confirmed the checkbox remained off. Restored on and saved. This is a real UI/persistence check; automatic text capitalization is covered by engine tests, not a claimed cross-app physical-keyboard pass.
- Native spelling/engine checks: `Done. hello → Hello`, `Done. a → A`, `Done. teh → The`, `Dr. smith` unchanged. The existing English writing fixes still pass.
- Claude's installed Electron 44.4.3 uses `Electron Framework.framework`. Detection includes that exact name. Preparation requests AXManualAccessibility once after success; transient failures retry at least five seconds apart, at most three attempts, without polling. This avoids resetting Electron's two-second activation delay on each word. App exclusions remain intact; Claude is not paused.
- Added an AXValue fallback when AXNumberOfCharacters is absent, retaining strict real-caret, value-size, range, focus, and physical-input checks. Snapshot and text writes are otherwise unchanged. Diagnostic phases can distinguish unsupported fields from input/verification failures without logging typed content.
- Universal arm64/x86_64 build and strict signature verification passed. ZIP: 225,098 bytes; SHA-256 `43b8d295e32676e0756a6878eb2fe453688ebe7f85cc0e7779740173c9d5ca7a`. Installed Accessibility, Input Monitoring, keyboard listener, and login registration checks pass.
- User-verified Claude desktop keyboard check after installation: typing `teh ` followed by `next` corrected to `the next`, with both words preserved. This is a user-confirmed real interaction, not an automated UI pass. Other applications are not assumed compatible from Claude alone.

Primary compatibility references: [Electron accessibility API](https://www.electronjs.org/docs/latest/tutorial/accessibility), [version-matched activation delay](https://github.com/electron/electron/blob/v44.4.3/shell/browser/mac/electron_application.mm), [Chromium character-count implementation](https://github.com/chromium/chromium/blob/main/ui/accessibility/platform/browser_accessibility_cocoa.mm).

---

# 0.2.2 validation

Checked September 29, 2026 on Apple silicon, macOS 26.6, Swift 6.4.

- All 45 tests passed, 0 failures. Added English writing-rule tests, candidate-to-replacement-plan tests preserving the next word, and actual CorrectionEngine integration tests with isolated preferences. Ignored words and custom corrections take precedence, including a parsed single-letter `i` entry.
- Native spelling smoke checks now return `i → I`, `im → I'm`, `i'm → I'm`, `ive → I've`, `doesnt → doesn't`, `dont → don't`, `didnt → didn't`, `cant → can't`, `wont → won't`, `youre → you're`, and `ti → it`. Existing `teh`, `ths`, and `mispell` samples still correct. `ill`, `well`, `were`, `its`, `world`, `Marko`, and `GitHub` remain unchanged.
- The new conventional writing rules apply only to English, preserve initial capitalization, and skip acronyms/mixed-case tokens. `ti`, `cant`, and `wont` are intentional prose defaults even where a dictionary has another meaning; users can ignore or override them. This is not a sentence-level grammar engine.
- Universal arm64/x86_64 build and strict signature verification passed. ZIP: 200,409 bytes. SHA-256: `06f276032181dad551ad5cf2154e787fc40a1bb1414d216d31eeff6857f6bdbc`.
- The keyboard replacement transport is unchanged from 0.2.1. Automated tests are not a physical-keyboard test of the current desktop chat composer; the previous direct-automation restriction still applies. No app exclusions were added.
- README now states the remaining 1.0 requirements rather than treating a version-number change as proof of readiness.

---

# 0.2.1 validation

Checked September 29, 2026 on Apple silicon, macOS 26.6, Swift 6.4.

- Replaced selected-text Accessibility writes with a prebuilt native keyboard sequence. Production Accessibility code now only reads the field and never creates a temporary selection. The old failure path could leave the replacement selected, letting the next typed key erase it.
- Revalidates focus, collapsed caret, snapshot text, physical-key counter, app exclusion, input source, and request generation before posting the edit. New input cancels an edit that has not started. A text-free trigger is consumed; all replacement events are inserted together from its event-tap callback.
- Verification is read-only and accepts continued typing after the expected replacement. Failed verification never retries deletion. No full-field replacement, clipboard use, or external service was added.
- Local native dictionary checks: `teh → the`, `ths → this`, `frm → from`, `thsi → this`, `helllo → hello`, `recieve → receive`, `speling → spelling`, `mispell → misspell`. `wth`, `world`, `Marko`, and `GitHub` remained unchanged. This is a sample, not a dictionary coverage measurement; ambiguous short words can still be wrong or left unchanged.
- The short-word policy uses ranked native guesses and general missing-letter rules, with surrounding text supplied to the native correction API. No fixed typo mapping was added.
- ChatGPT was not added to the excluded apps. Existing preferences, ignored words, custom corrections, permissions, and login registration are preserved.
- Direct automation of the user's current desktop chat app was blocked by the computer-use tool. Attempts in disposable TextEdit/Chrome fields did not establish a physical-keyboard end-to-end result. **Desktop ChatGPT compatibility and the full real-typing path remain unverified**; do not treat unit/event-construction tests as that verification.
- Native keyboard delivery is not an atomic text-edit API. Editors that reject synthetic input may still be unsupported. Backspace edits are limited to ASCII originals and delimiters; Unicode prefixes and replacement payloads are preserved.

- All 38 tests passed with 0 failures: 34 policy/dictionary/replacement-plan tests plus 4 native CGEvent-to-NSEvent construction tests. The native tests verify exact key-down payloads, backspace order, paired key-up events, cleared modifiers, synthetic markers, Unicode/case/contractions, and simulated next-word preservation. They do not post events to another application.
- Universal arm64/x86_64 release compilation and strict signature verification passed. Final ZIP: 194,602 bytes; SHA-256 `8e862173ce809f96f6715cea9dab7771dd399840d5445dcde0a43382c44236b8`.
- Installed app retains Accessibility and Input Monitoring permission and enabled login registration. Exact desktop-editor behavior still requires the interactive check stated above.

---

# 0.2.0 validation

Checked September 29, 2026 on Apple silicon, macOS 26.6, Swift 6.4.

- 21 core tests passed, 0 failed: original correction policy, Unicode/case handling, dictionary parsing and validation, custom-source case exceptions, and preservation of structured-token protections.
- Universal arm64/x86_64 release built and signed successfully. Installed update passes strict signature verification.
- Native Settings window visually inspected. English (US) selected by default; underline toggle enabled; approval toggle off.
- Real UI test added an ignored word and a custom correction, saved them, relaunched, and confirmed both persisted with exact replacement casing. Both temporary entries were removed through the UI and empty saved lists were verified afterward.
- Native spelling smoke checks passed for teh, helllo, recieve, and speling; world, Marko, and GitHub unchanged.
- Accessibility and Input Monitoring both report false on this installation. Actual cross-app correction, menu approval, undo, and red underline placement remain unverified until the user grants access. The overlay's code compiles; compilation is not a visual placement test.
- Underlines are transient, apply to the most recently completed word, and require usable AX bounds. They are not persistent full-document markings.
- No complete inventory of English words is bundled or claimed; the app consults Apple's local spelling dictionaries. Uncertain suggestions require review. User-specified replacements preserve exact spelling; ignored words take precedence.

---

# 0.1.0 validation

Checked September 28, 2026 on Apple silicon, macOS 26.6, Swift 6.4 / Xcode 27 SDK.

| Check | Result |
| --- | --- |
| Correction policy tests | 9 tests passed, 0 failed; UTF-16, token exclusions, punctuation, capitalization, and confidence rules |
| Release compilation | arm64 and x86_64 passed |
| GitHub Actions | Clean hosted macOS build, all policy tests, universal packaging, and artifact upload passed |
| Homebrew distribution | Project tap installed; published release fetched and its SHA-256 verified successfully |
| Bundle validation | plist valid; both architectures present; strict code-signature verification passed for clean archive and installed app |
| Local installation and launch | Installed in /Applications; background process running |
| Launch at login registration | SMAppService reports enabled; an actual logout/login has not been exercised |
| Native spelling smoke check | teh → the, helllo → hello, recieve → receive, speling → spelling; world, Marko, GitHub unchanged |
| Release ZIP | 108,635 bytes; ad-hoc signed, not notarized |
| Installed app disk allocation | 360 KiB for the locally development-signed universal bundle |
| Idle process snapshot | Approximately 49 MiB RSS and 0.0% CPU; permissions were not granted, so this is not an active-typing or battery benchmark |
| Accessibility and Input Monitoring | Both awaiting the user's macOS approval |
| End-to-end correction, approval, undo, rapid typing | Not verified: permissions required |
| TextEdit, Chrome, ChatGPT, Claude compatibility | Not verified: permissions required |
| Menu interaction via automation | Tool could not inspect the background-only app; no UI interaction pass is claimed |

The release has no bundled AI model, browser runtime, or third-party dependencies. System frameworks and macOS spelling services are not included in the bundle size.

## Required interactive check

Grant both permissions in System Settings, reopen AutoCorrect, and use a disposable document. Type `teh ` and `recieve ` with the host app's own autocorrection off so the result is attributable to AutoCorrect. Verify approval mode and its menu action, immediate undo, app exclusions, emoji before the word, cursor movement, and typing the next word rapidly. Repeat in each desired app.

Cross-process Accessibility writes are not atomic. The app uses an active event tap, 10 ms AX timeouts, a short edit budget with cleanup reserve, physical-key counters, and exact field/selection/text revalidation. Unresponsive or unusual controls can still fail; skipped edits are preferred over forcing changes. Do not infer universal compatibility from the unit tests.
