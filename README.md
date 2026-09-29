# AutoCorrect

A small native macOS menu bar app that corrects spelling when you finish typing a word. It uses Apple's built-in spell checker on your Mac. No accounts, subscriptions, network services, downloaded models, or third-party dependencies.

Requires **macOS 13 Ventura or later**, on Apple silicon or Intel.

**0.3.0 is a preview.** Unit tests, universal packaging, local launch, and login registration have been checked. Compatibility with individual editors and underline placement still need real keyboard testing; see [validation](docs/VALIDATION.md).

## What it does

- English writing rules capitalize standalone `i`, repair `im → I'm` and common missing apostrophes (`doesnt → doesn't`, `dont → don't`), and correct `ti → it`. Ignored words and custom corrections override these defaults. Valid ambiguous words such as `ill`, `well`, and `were` are preserved. Nearby-word rules suggest `its/it’s` and `lets/let’s` changes for narrow contexts; these always require approval.
- Built-in abbreviation expansions: `idk → I don't know`, `omw → On my way`, `brb → Be right back`, `imo → in my opinion`, and `fyi → for your information`. Product/acronym casing includes `iphone → iPhone`, `ui → UI`, `ux → UX`, `api → API`, and `macos → macOS`. Both groups have independent switches in Text Replacements. Ignoring a shortcut disables it individually.
- **Automatic mode:** replaces a misspelled word after a supported word boundary, such as a space.
- **Approval mode:** offers a correction through the menu bar so you can decide whether to apply it. Suggestions expire after 30 seconds and are canceled by your next key press.
- Undo the most recent correction with **Control–Option–Command–Z** or the menu bar, even after continuing to type. Undo lasts up to five minutes while the unchanged correction and its context remain within the bounded text window (up to 96 ASCII characters after it). It restores the original word or abbreviation and preserves following text. It does not replace your editor’s Command–Z.
- A custom letter/checkmark menu bar icon and a native app window with Overview, Writing, Text Replacements, Ignored Words, and Apps. To pause one app, open that app, then choose **AutoCorrect → Pause in [app]**. Choose **Resume in [app]** to turn it back on. The Paused Apps submenu only lists apps installed on your Mac.
- **Settings → Ignored Words:** add names or words that should never be corrected or marked. Remove a word to check it again. Matching ignores capitalization.
- **Settings → Text Replacements:** choose a typed shortcut and its replacement phrase (up to 120 characters), including exact capitalization. Add the same typed word again to update it. Ignored words take precedence over custom corrections.
- **Settings → Writing → Capitalize after a period:** enabled by default. Capitalizes the next completed word when you type its space or punctuation (`Done. hello ` → `Done. Hello `). Turn it off independently of spelling correction. Common abbreviations, initials, decimals, URLs, and ambiguous period endings are skipped. Ignored words and exact custom replacements keep priority.
- **Show Spelling Underlines:** optionally draw a red wavy underline beneath the latest completed possible misspelling. This requires the host app to expose the word's on-screen bounds. It clears on typing, clicking, scrolling, app switching, or after five seconds. It does not continuously mark the whole document.
- English (US) is the default; the language selector is in Settings. Uncertain dictionary suggestions require approval even in automatic mode.
- Automatically requests launch at login on first launch; you can turn it off in the menu bar.
- Uses read-only macOS Accessibility to check the field, then native keyboard input to correct it without temporarily selecting the word.
- Runs in the background without a Dock icon. Settings opens only when requested.

This release handles **spelling, text expansion, capitalization, and a narrow set of contextual English suggestions**. It does not provide comprehensive grammar, tone, or rewriting. Apple's dictionaries cover common and uncommon words, but are not an exhaustive list of every English word, name, or technical term. Short missing-letter typos now use native-ranked suggestions too: for example, `ths → this` and `frm → from`. Longer misspellings can use the first native-ranked guess, with edit-distance and ambiguity checks (`capitazed → capitalized` on the development Mac). These are general edit rules, not a fixed list of typos; ambiguous words can still be wrong or left unchanged. A misspelling without a reliable automatic correction is flagged for review when supported; no correction is guaranteed for every word.

## Install

Download `AutoCorrect-0.3.0-universal.zip` from [Releases](https://github.com/markoderic/autocorrect/releases), unzip it, and move **AutoCorrect.app** to **Applications**. Open it and look for its menu bar item.

Release builds are **ad-hoc signed and not Apple notarized**. macOS may block the first launch of a downloaded copy. If you trust the source, attempt to open the app, then go to **System Settings → Privacy & Security → Open Anyway** and confirm. Follow the macOS instructions shown for your version. You do not need to disable Gatekeeper.

### Permissions

Open **AutoCorrect → Permissions** and grant the permissions it requests in **System Settings → Privacy & Security**:

1. **Accessibility:** lets AutoCorrect inspect the focused text field and replace the completed word.
2. **Input Monitoring:** lets AutoCorrect notice word boundaries while you type in another app.

macOS requires you to approve these permissions yourself. If you change permissions, quit and reopen AutoCorrect. Install it in its permanent location before the first launch. AutoCorrect automatically attempts to enable launch at login on first launch; macOS may require approval under **System Settings → General → Login Items**. The menu shows the actual status and lets you retry or disable it.

If a rebuilt app stops working, check its permissions again. Ad-hoc signatures can change between builds. Developers can use a stable local signing identity with the build script.

### Homebrew

Install the project-maintained cask:

```sh
brew tap markoderic/autocorrect https://github.com/markoderic/autocorrect.git
brew install --cask markoderic/autocorrect/autocorrect
```

The cask installs the same app and has the same permissions and first-launch requirements. It is a project-maintained cask, not part of the official Homebrew cask collection.

## Compatibility and privacy

AutoCorrect relies on each app exposing a usable text field through macOS Accessibility. For Electron apps such as Claude and detected Chromium browsers, it requests accessibility support on activation. Some apps need about two seconds to expose their text tree. Successful requests are made once per process launch; transient failures have bounded retries. Rich editors without a character-count attribute can use a bounded text-value fallback when they expose a real caret. Some browser editors, custom controls, terminals, remote desktops, and apps with restricted accessibility will not work. It skips password fields, unsupported fields, and input methods that use composition (IME). Common coding apps, terminals, and password managers are paused by default; use **Paused Apps** to change those exclusions. It checks that the focus, selection, and surrounding text still match before applying a correction. Corrections no longer write selected text through Accessibility, which could leave a word selected and cause the next keystroke to overwrite it. A complete keyboard edit is prepared before anything is deleted; stale edits are canceled, and verification never retries a deletion. Deleted words/phrases and any replayed following text must be ASCII for predictable backspace behavior; the preceding text and replacement may contain Unicode. Fast typing retains up to eight completed-word boundaries and briefly retries stale Accessibility reads. Navigation, focus changes, and editing commands cancel those pending checks. It does not promise support for every app.

Spelling checks run locally through `NSSpellChecker`. AutoCorrect does not send your text to a server or save a typing history. It inspects at most 256 UTF-16 units before the cursor, with a bounded fallback for small fields, and caches up to 256 spelling results in memory. App exclusions, deliberately ignored words, and settings are stored locally. macOS may also apply its own spelling corrections; if you see conflicting behavior, disable one of the correction systems for that app.

The implementation is event-driven rather than continuously polling. It uses native system APIs, with no embedded browser or language model. Exact CPU, memory, and battery use depend on the app and workload; a long-duration power benchmark has not been completed.

## Build and run

Install Xcode Command Line Tools and use a Swift 5.9 or newer toolchain:

```sh
xcode-select --install
git clone https://github.com/markoderic/autocorrect.git
cd autocorrect
swift test --build-system native
./scripts/build.sh
./scripts/install.sh
```

The build script compiles **arm64 and x86_64**, combines them into a universal executable, strips it, signs the app, and writes:

```text
dist/AutoCorrect.app
dist/AutoCorrect-0.3.0-universal.zip
dist/AutoCorrect-0.3.0-universal.zip.sha256
```

It can be called from any working directory. The installer uses `/Applications` when writable, otherwise `~/Applications`. Use `--user` to choose `~/Applications`, `--no-open` to install without launching, and `--replace` to replace an existing installation. Quit AutoCorrect before replacing it; the installer preserves the previous bundle alongside the new one.

To use an existing local signing identity:

```sh
SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build.sh
```

A local development signature is not a notarized distribution release. The repository contains no signing credentials.

## Verify

`swift test --build-system native` exercises the pure correction policy. The GitHub Actions workflow runs those tests and builds a universal app archive. Building or passing unit tests does **not** verify macOS permissions, real typing behavior, login behavior, or compatibility with a particular app.

The installed binary also supports `--diagnostics` (permission and login status only) and `--check-spelling` (fixed sample words only). Neither command reads another app's text. Developers can launch a single app instance with `--trace` to print fixed diagnostic phase labels (boundary, snapshot, edit, verification), never typed text or app names. Normal operation does not log these phases.

For a manual check after granting permissions:

1. Open a disposable plain text document in TextEdit. Type `teh `, `ths `, `mispell `, and then continue with `next word`. Confirm the correction and the following text both remain, with no selection left behind. Repeat with punctuation and emoji before the misspelling.
2. Switch on **Ask Before Correcting**. Type a misspelling and a space, then open the menu without typing another key. Confirm the text stays unchanged until you choose **Apply** within 30 seconds.
3. Move the cursor or change focus before approving. Confirm a stale suggestion does not change another field.
4. Exclude TextEdit, then repeat the misspelling and confirm AutoCorrect leaves it alone.
5. Type `idk next`, confirm `I don't know next`, then press Control–Option–Command–Z and confirm `idk next`. Try fast `i ths next`, sentence capitalization on/off, and `lets go` (approval only).
6. Try the apps you use every day. Treat fields that do not work as unsupported.
7. Check **Launch at Login** and verify it after your next login.

## Publish a release

`./scripts/release.sh` prepares the archive and checksum locally. Set `VERSION` to build another version. Before publishing, update the cask's version and SHA-256 to match the exact final archive, and upload the archive to the matching GitHub `vVERSION` release. The release script does not publish anything itself.

## Uninstall

Turn off launch at login, quit AutoCorrect from the menu bar, and remove the app. For a Homebrew installation, use `brew uninstall --cask markoderic/autocorrect/autocorrect`. Remove its Accessibility and Input Monitoring entries in System Settings if desired. Local preferences are retained unless you remove them separately.

## License

[MIT](LICENSE) · Copyright © 2026 Marko Deric

See the [research and tradeoffs](docs/RESEARCH.md) and [release validation](docs/VALIDATION.md).

## What 1.0 means

The 0.x version marks a preview, not a paid tier or a percentage of completion. Before 1.0, the project needs a larger English regression corpus (including contractions, capitalization, punctuation, short typos, valid words, and user dictionaries), verified real-keyboard behavior in a stated list of native and browser editors, rapid-typing and focus-change tests with no text loss, working approval/undo, measured active/idle resource use, and a dependable signed/notarized install and update process. 0.3.0 adds the native app window, wider regression coverage, expansions, contextual suggestions, and continued-typing undo. Remaining release gates include a documented physical-keyboard app matrix, stress/undo verification across editors, sustained resource measurements, and notarized distribution. The exact desktop chat composer has not yet been independently verified. A version number alone cannot establish reliability, and 1.0 will not promise every English word or every application.
