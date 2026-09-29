# 0.3.5 validation

Checked September 29, 2026 on the development Mac.

- **134 automated tests passed, 0 failures.** New tests cover question/exclamation/mixed endings, quotes and brackets, full typing previews, single-letter capitalization, joined-word sentence starts, product casing, feature-off behavior, ignored/custom overrides, six broader native spelling repairs, and actual pending-proposal state in automatic versus review mode. Existing edit, undo, manual rewrite, and structured-token checks remain in the suite.
- Capitalization now recognizes `.`, `?`, and `!` before whitespace and capitalizes the next completed word. The stored preference key is unchanged, preserving the user's toggle. Existing period abbreviation/decimal/URL guards remain. This does not capitalize immediately on the first keystroke of the new word.
- A native automatic recommendation matching its first guess can now repair two edits in words of at least five letters (at most 40 percent of the source length). A strictly closer top-five alternative blocks this fallback; equal-distance alternatives no longer block it when both native signals agree. This is a deliberate coverage tradeoff, not a measured general accuracy increase.
- Automatic mode never creates a pending approval proposal for weak guesses. They retain an optional underline and menu indication. Ask Before Correcting still creates a proposal, and previews identify approval mode. No unreliable guess is blindly applied solely to eliminate the approval UI.
- Universal Intel/Apple silicon compilation and exact-archive signature, architecture, and license checks passed. ZIP size: 1,604,280 bytes. SHA-256: `26826d8a8b38129882dbfceba6c57744d285cb0ac30612386f2a5b6b06df9e43`. Public archive remains ad-hoc signed and not notarized.
- Installed 0.3.5 with the existing development signing identity and confirmed the running process. Installed diagnostics report Accessibility, Input Monitoring, supported layout, keyboard-listener capability, and enabled login registration. Fixed installed probes confirm question/exclamation capitalization and the broader spelling examples. Ask Before Correcting is off and sentence capitalization is on in the existing preferences.
- No new physical-keyboard or all-editor overlay validation is claimed. Tests verify the policies and menu state, not every host app's event handling or dictionary behavior on every macOS release.

---

# 0.3.4 validation

Checked September 29, 2026 on the development Mac.

- **129 automated tests passed, 0 failures.** Actual native-checker integration covers nine joined-word examples, valid compounds/filenames, user overrides, the new automatic-spacing setting, reported straight/curly apostrophes, contextual `pleas help`, and plural-noun counterexamples. Shared edit-plan tests confirm smart-apostrophe deletion, exact following-text preservation, and reversal of `I know` back to `iknow`. Geometry fixtures cover missing whole-word bounds, missing endpoint bounds with equal line indices, wrapped lines, and invalid rectangles. Existing context, manual rewrite, undo, and transport tests remain in the suite.
- Before changes, straight-apostrophe `doen'st` already passed engine assessment. The actual bug found was rejection of curly apostrophes in the shared replacement plan. This is a confirmed implementation gap, not proof that smart punctuation explains every missed correction in every host app.
- Universal arm64/x86_64 builds and exact-archive signature, architecture, and bundled-license checks passed. ZIP: 1,600,404 bytes. SHA-256: `e3b0ef9f4aacd49e49fecd99ebe7597e3ba940afe0fb7719f91bd90a8473f242`. Public build is ad-hoc signed and not notarized.
- Installed 0.3.4 with the existing local development signing identity and relaunched it. Process and installed diagnostics confirm Accessibility, Input Monitoring, active keyboard-listener capability, supported layout, and enabled login registration. Fixed installed-engine probes confirm `doen'st`, `doen’st`, `does’nt`, `iknow`, `thankyou`, `inthe`, and `myfriend` corrections; standalone valid `pleas` remains unchanged.
- No new physical-keyboard or rendered-overlay cross-app pass is claimed. The CUA launch call timed out on the menu-only app, but the new process and versioned diagnostics independently confirmed startup. Geometry tests establish fallback decisions, not every editor's actual AX support.
- No native macOS/other-app preference is changed. Research found per-editor controls and cached WebKit defaults, not a reliable live system-wide off/on contract. See [research and limitations](SPACING-AND-UNDERLINES.md). Persistent document-wide underlines, unrestricted semantic correction, all-app compatibility, and measured battery usage remain outside the evidence.

---

# 0.3.3 validation

Checked September 29, 2026 on the development Mac.

- **124 automated tests passed, 0 failures.** New tests exercise the actual native checker for ten damaged contraction spellings, nineteen product/company/format spellings, nine name typos, thirteen larger ordinary-word typos, ordinary-word counterexamples, technical recognition, ignored/custom-word precedence, and full filename/URL typing. Deterministic policy tests cover native-candidate ambiguity, language/case gates, period/colon deferral, and strict three-edit fallback requirements. Existing context, undo, manual rewrite, and event-construction tests remain in the suite.
- Examples passing through the actual correction engine include `doenst / dosent / dosen't → doesn't`, `woudlnt → wouldn't`, `didtn → didn't`, `powerpoint / powerpiont → PowerPoint`, `microsfot → Microsoft`, `figmaa → Figma`, `kubernets → Kubernetes`, and `pdf → PDF`. Correct ordinary words such as `apple`, `word`, `excel`, `slack`, and `docent` stay unchanged.
- 6,231 recognition terms and 2,234 canonical name entries were generated from pinned CSpell company/software/filetype data. These include components of multiword names; the counts are not distinct-company totals or accuracy percentages. The [source manifest](lexicon-sources.json), generator, and MIT attribution are included. The exact public app archive contains `THIRD_PARTY_NOTICES.md`.
- The new name lookup microbenchmark, compiled with `swiftc -O`, measured 12.480 ms for first lookup including lazy index creation and 0.0041 ms mean over 3,000 warm synthetic lookups. This excludes native spell checking, event transport, and app UI; it is not an end-to-end typing/battery benchmark.
- Periods and colons now defer word assessment until another delimiter. Full typing previews preserve `doenst.txt`, `powerpoint.pptx`, `iphoen.png`, email/URL/path tokens, and underscores. A plain sentence ending `it doenst. ` becomes `it doesn't. ` after its trailing space. Ordinary words separated by spaces inside a filename cannot always be distinguished from prose; no filesystem scan is performed.
- Universal arm64/x86_64 compilation, exact-archive checksum, strict ad-hoc signature, and bundled license checks passed. Archive size: 1,590,346 bytes. SHA-256: `84ff5beea5ef2ae1963cca619954919573f15ced6ab31705a7f081efd3b4051d`. This remains a preview, not Apple notarized.
- Installed 0.3.3 using the existing development identity. Diagnostics confirm Accessibility, Input Monitoring, keyboard listener, supported layout, and enabled launch-at-login registration; fixed installed-engine probes confirm the new examples.
- No new physical-keyboard app compatibility pass is claimed. The new tests establish dictionary/engine/queue behavior; real typing in each host app, foreground races, and long-duration power measurements remain separate validation work. Arbitrary semantic substitutions and all company/person names are not guaranteed.

---

# 0.3.2 validation

Checked September 29, 2026 on the development Mac.

- **112 automated tests passed, 0 failures.** New integration tests call the actual native spell checker for product typos, missing-letter cases, and five screenshot typos in four sentence contexts. Core fixtures cover conservative short-word ambiguity, each boundary's one-spelling/one-context edit limit, contextual positive/negative cases, approval/settings overrides, following-text preservation, undo anchors, and manual rewrite protection.
- `github → GitHub`, `iphoen / iphne / iphnoe → iPhone`, and `githbu / githb → GitHub` pass, including canonical `iPhone` after a period. Correct `screenshot`, `homebrew`, ordinary `phone` / `siphon`, mixed-case product names, and structured tokens remain unchanged in the checked fixtures.
- Automatic context examples pass: `lets improve this`, `okay, lets fix this`, `its a screenshot`, `its ready.`, `its working now`, and `it's screen is broken`. Valid `she lets go`, `its good looks`, `its working parts`, `its ready meals`, and `despite its not working` are preserved. A following word or punctuation is needed: bare `its` / `lets` and incomplete adjective contexts stay unchanged.
- Queued context checks now use each completed prefix, including when another word has begun. Each boundary can post at most one spelling edit and one context edit, preventing cycles between custom replacements. This is covered at the queue/policy/plan level; it is not a real typing speed measurement.
- Both arm64 and x86_64 release builds passed. Public archive: 1,495,142 bytes. SHA-256: `6280e46e273072105c1a7d009f8103b7cddf9e4d16d26b97e5b111d6638bd668`. Public build is ad-hoc signed and not notarized.
- Installed 0.3.2 with the existing local development signing identity. Its diagnostics report Accessibility, Input Monitoring, keyboard listener, supported input source, and enabled login registration. Existing preferences were retained. The installed binary's fixed spelling/context checks confirm the examples above.
- **No new physical-keyboard compatibility pass is claimed.** The computer-use tool typed a disposable TextEdit fixture in the background while macOS still identified another app as frontmost; the fixture was not corrected. That does not exercise this utility's foreground-keyboard path. The fixture was saved separately and closed; existing documents were not edited. ChatGPT/Claude delivery, rapid typing, and native undo still require real foreground typing to establish end-to-end behavior.
- `har` is accepted by the local dictionary and remains unchanged. The app does not yet infer an arbitrary intended word from sentence meaning. This is bounded local spelling/context logic, not Grammarly-equivalent semantic correction, a held-out accuracy benchmark, or a 1.0 certification.

---

# 0.3.1 validation

Checked September 29, 2026 on Apple silicon, macOS 26.6, Swift 6.4.

- **105 tests passed, zero failures**, including manual rewrite loops, alternate manual spellings, unchanged/different occurrences, field/context mismatches, canceled/unconfirmed edits, native-undo edit signals, confirmed-override retention, bounded history eviction, and compound-word ranking. The event-tap placement was also independently reviewed for registration-before-posting and lifecycle safety. Tests exercise the policy and actual engine assessment; they do not simulate physical typing in every editor.
- Manual rewrite protection remembers at most eight recent correction occurrences in the active field. A deletion, native undo, or mouse edit followed by changed spelling at the same exact location/context protects that occurrence. Confirmed overrides persist until field/settings reset or bounded-history eviction. Unconfirmed records expire after two minutes. No permanent ignored-word preference is written.
- The installed engine reports `homebrew → (unchanged)`, while `teh → the`, `idk → I don't know`, `iphone → iPhone`, `ui → UI`, and `capitazed → capitalized` still pass. A generic native compound suggestion rule prevents replacing identical joined letters with a different word. It can still offer the spaced form for review.
- The new menu image is 20×18 points. A 2× native raster measures 40×36 pixels, with visible bounds x=4…35 and y=7…28: the mark is centered on both axes and occupies about 16×11 points. The application icon is unchanged.
- Universal arm64/x86_64 release build and strict signature verification passed. Archive: 1,471,501 bytes; SHA-256 `af8f127bb9f7b81e6eb8cb171ebbe80c5a8e3166e2f3119c76e63ebafb0e9b0e`. Installed Accessibility, Input Monitoring, keyboard listener, keyboard layout, and launch-at-login registration remain enabled. The app runs without trace logging.
- Created an 18-second 1280×720, 24 fps MP4 with Higgsfield/Higgsedit, plus an 800×450 looping GIF and poster. Main frames were visually inspected. All visuals are authored examples and labeled **Illustrated demo**, not a real editor recording or compatibility test. The editable composition and assets are in `docs/media/`. A LinkedIn draft is kept outside tracked source under ignored `dist/launch/`; nothing was sent or posted to LinkedIn.

---

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
