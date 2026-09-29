# AutoCorrect

A small native macOS menu bar app that corrects spelling when you finish typing a word. It uses Apple's built-in spell checker on your Mac. No accounts, subscriptions, network services, downloaded models, or third-party dependencies.

Requires **macOS 13 Ventura or later**, on Apple silicon or Intel.

**0.2.2 is a preview.** Unit tests, universal packaging, local launch, and login registration have been checked. Compatibility with individual editors and underline placement still need real keyboard testing; see [validation](docs/VALIDATION.md).

## What it does

- English writing rules capitalize standalone `i`, repair `im → I'm` and common missing apostrophes (`doesnt → doesn't`, `dont → don't`), and correct `ti → it`. Ignored words and custom corrections override these defaults. Ambiguous words such as `ill`, `well`, `were`, and `its` are left to the spelling checker.
- **Automatic mode:** replaces a misspelled word after a supported word boundary, such as a space.
- **Approval mode:** offers a correction through the menu bar so you can decide whether to apply it. Suggestions expire after 30 seconds and are canceled by your next key press.
- Undo the most recent correction from the menu bar immediately, before your next key press or the 30-second timeout.
- A simple **Aa** menu bar icon. To pause one app, open that app, then choose **Aa → Pause in [app]**. Choose **Resume in [app]** to turn it back on. The Paused Apps submenu only lists apps installed on your Mac.
- **Settings → Ignored Words:** add names or words that should never be corrected or marked. Remove a word to check it again. Matching ignores capitalization.
- **Settings → Custom Corrections:** choose a typed word and its replacement, including exact capitalization. Add the same typed word again to update it. Ignored words take precedence over custom corrections.
- **Show Spelling Underlines:** optionally draw a red wavy underline beneath the latest completed possible misspelling. This requires the host app to expose the word's on-screen bounds. It clears on typing, clicking, scrolling, app switching, or after five seconds. It does not continuously mark the whole document.
- English (US) is the default; the language selector is in Settings. Uncertain dictionary suggestions require approval even in automatic mode.
- Automatically requests launch at login on first launch; you can turn it off in the menu bar.
- Uses read-only macOS Accessibility to check the field, then native keyboard input to correct it without temporarily selecting the word.
- Runs in the background without a Dock icon. Settings opens only when requested.

This release handles **spelling and a small set of English writing rules**. It does not provide sentence-level grammar, tone, or rewriting. Apple's dictionaries cover common and uncommon words, but are not an exhaustive list of every English word, name, or technical term. Short missing-letter typos now use native-ranked suggestions too: for example, `ths → this` and `frm → from`. These are general edit rules, not a fixed list of typos; ambiguous words can still be wrong or left unchanged. A misspelling without a reliable automatic correction is flagged for review when supported; no correction is guaranteed for every word.

## Install

Download `AutoCorrect-0.2.2-universal.zip` from [Releases](https://github.com/markoderic/autocorrect/releases), unzip it, and move **AutoCorrect.app** to **Applications**. Open it and look for its menu bar item.

Release builds are **ad-hoc signed and not Apple notarized**. macOS may block the first launch of a downloaded copy. If you trust the source, attempt to open the app, then go to **System Settings → Privacy & Security → Open Anyway** and confirm. Follow the macOS instructions shown for your version. You do not need to disable Gatekeeper.

### Permissions

Open **Aa → Permissions** and grant the permissions it requests in **System Settings → Privacy & Security**:

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

AutoCorrect relies on each app exposing a usable text field through macOS Accessibility. Some browser editors, custom controls, terminals, remote desktops, and apps with restricted accessibility will not work. It skips password fields, unsupported fields, and input methods that use composition (IME). Common coding apps, terminals, and password managers are paused by default; use **Paused Apps** to change those exclusions. It checks that the focus, selection, and surrounding text still match before applying a correction. Corrections no longer write selected text through Accessibility, which could leave a word selected and cause the next keystroke to overwrite it. A complete keyboard edit is prepared before anything is deleted; stale edits are canceled, and verification never retries a deletion. Original words and their trailing delimiters must be ASCII for predictable backspace behavior; the preceding text and replacement may contain Unicode. It does not promise support for every app.

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
dist/AutoCorrect-0.2.2-universal.zip
dist/AutoCorrect-0.2.2-universal.zip.sha256
```

It can be called from any working directory. The installer uses `/Applications` when writable, otherwise `~/Applications`. Use `--user` to choose `~/Applications`, `--no-open` to install without launching, and `--replace` to replace an existing installation. Quit AutoCorrect before replacing it; the installer preserves the previous bundle alongside the new one.

To use an existing local signing identity:

```sh
SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build.sh
```

A local development signature is not a notarized distribution release. The repository contains no signing credentials.

## Verify

`swift test --build-system native` exercises the pure correction policy. The GitHub Actions workflow runs those tests and builds a universal app archive. Building or passing unit tests does **not** verify macOS permissions, real typing behavior, login behavior, or compatibility with a particular app.

The installed binary also supports `--diagnostics` (permission and login status only) and `--check-spelling` (fixed sample words only). Neither command reads another app's text.

For a manual check after granting permissions:

1. Open a disposable plain text document in TextEdit. Type `teh `, `ths `, `mispell `, and then continue with `next word`. Confirm the correction and the following text both remain, with no selection left behind. Repeat with punctuation and emoji before the misspelling.
2. Switch on **Ask Before Correcting**. Type a misspelling and a space, then open the menu without typing another key. Confirm the text stays unchanged until you choose **Apply** within 30 seconds.
3. Move the cursor or change focus before approving. Confirm a stale suggestion does not change another field.
4. Exclude TextEdit, then repeat the misspelling and confirm AutoCorrect leaves it alone.
5. Try the apps you use every day. Treat fields that do not work as unsupported.
6. Check **Launch at Login** and verify it after your next login.

## Publish a release

`./scripts/release.sh` prepares the archive and checksum locally. Set `VERSION` to build another version. Before publishing, update the cask's version and SHA-256 to match the exact final archive, and upload the archive to the matching GitHub `vVERSION` release. The release script does not publish anything itself.

## Uninstall

Turn off launch at login, quit AutoCorrect from the menu bar, and remove the app. For a Homebrew installation, use `brew uninstall --cask markoderic/autocorrect/autocorrect`. Remove its Accessibility and Input Monitoring entries in System Settings if desired. Local preferences are retained unless you remove them separately.

## License

[MIT](LICENSE) · Copyright © 2026 Marko Deric

## What 1.0 means

The 0.x version marks a preview, not a paid tier or a percentage of completion. Before 1.0, the project needs a larger English regression corpus (including contractions, capitalization, punctuation, short typos, valid words, and user dictionaries), verified real-keyboard behavior in a stated list of native and browser editors, rapid-typing and focus-change tests with no text loss, working approval/undo, measured active/idle resource use, and a dependable signed/notarized install and update process. The exact desktop chat composer has not yet been independently verified. A version number alone cannot establish reliability, and 1.0 will not promise every English word or every application.
