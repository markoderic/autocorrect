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
