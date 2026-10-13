# Signed and notarized Mac distribution

The public **0.3.14 preview is Developer ID signed and Apple notarized**. Its browser-downloaded ZIP matches the published checksum; the extracted app passes Gatekeeper with browser quarantine retained. This addresses the older preview's “Apple cannot check it for malicious software” block. Accessibility and Input Monitoring permissions remain separate.

Download the [new release](https://github.com/markoderic/autocorrect/releases/tag/v0.3.14) rather than reusing an old ZIP. macOS can still ask whether to open an app downloaded from the Internet; see [Apple's explanation](https://support.apple.com/en-us/102445). Do not disable Gatekeeper or remove quarantine as an installation step. Another-Mac first launch remains to be checked.

## Maintainer prerequisites

1. An active Apple Developer Program team and a **Developer ID Application** certificate with its private key in the build Mac's keychain. An **Apple Development** certificate is not interchangeable. The account holder may need to create the Developer ID certificate.
2. An existing `notarytool` keychain profile with authorized notarization credentials. Store credentials interactively with `xcrun notarytool store-credentials`; do not put passwords, private keys, or API keys into this repository or chat.
3. Run the tests before building. Keep the local development signature for local installs so existing Accessibility permission identity remains stable.

On September 29, 2026, the development Mac had only an Apple Development signing identity. There were no repository signing secrets. No notarization submission or successful Gatekeeper assessment is claimed for 0.3.7.

## Current setup — October 13, 2026

The owner's existing Developer Program account provides **Developer ID Application: Marko Deric (B376DM5LNP)**. Its private key and the authorized `AutoCorrect-notary` profile remain in the local Keychain. Existing Apple Development/App Store certificates are preserved.

**0.3.14 is signed and notarized.** Submission `b7fb4e72-7e04-4cc5-9a5f-285974c01ab3` is Accepted. Its ticket is stapled; the final extracted ZIP passes strict signature, both architectures, Gatekeeper (`Notarized Developer ID`) and `syspolicy_check distribution`. SHA-256: `5aaadc913aa7c050683d1d5943944c1a4de5ed0fd572756841381cdbfec51898`. Public release: [v0.3.14](https://github.com/markoderic/autocorrect/releases/tag/v0.3.14). It remains a preview for accuracy/compatibility, independent of notarization status.

The earlier local 0.3.13 submission `6be10b1c-e7d6-48d0-abcf-29e29c257104` was also Accepted; it was not published. The installed development signature is retained to preserve permissions. Public downloads use the separate Developer ID archive. A clean browser download and first launch on another Mac still need user verification.

Create a **Developer ID Application** certificate through Xcode's account certificate manager or [Apple's certificate portal instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/). Use the existing account; no second membership is needed. Creating a certificate in Xcode keeps its private key on this Mac. If importing an existing certificate, it also needs its corresponding private key. Do not revoke existing App Store or development certificates.

Then store a notarization profile interactively in Terminal:

```sh
xcrun notarytool store-credentials AutoCorrect-notary
```

Follow the local prompts for the account/team and an app-specific password (or use an existing authorized API-key profile). Never paste credentials in chat or source. Verify the setup without building or submitting anything:

```sh
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
NOTARY_PROFILE='AutoCorrect-notary' ./scripts/release.sh --check
```

This verifies that the identity/private key is locally available and authenticates with Apple's read-only notarization history endpoint. It cannot establish that a future upload will be accepted.

## Build a notarized release

```sh
swift test --build-system native
VERSION=0.3.14 \
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
NOTARY_PROFILE='your-existing-keychain-profile' \
./scripts/release.sh
```

The stable path checks the installed identity and authenticates credentials before building. The default version comes from `Resources/Info.plist`; `VERSION` can override it. `DIST_DIR` selects the same output folder for build, notarization results, final archive and checksum. Use a separate folder such as `DIST_DIR="$PWD/dist/notarized"` to preserve the local development build. `build.sh` enables hardened runtime and a secure timestamp for Developer ID signatures. `notarize.sh` verifies the signature, stages a copy, submits it to Apple, requires **Accepted**, staples the ticket, and runs Gatekeeper assessment. It then archives and extracts the final download and verifies the extracted app again before replacing the outputs. Rejection leaves the prior bundle/archive untouched. Submission results are in ignored `dist/notarization/`.

Only then update the Homebrew cask with the final ZIP checksum, upload that exact ZIP and checksum to GitHub, and label the release notarized. A checksum from before stapling is not valid for the final artifact. Public first launch still needs validation on a separate Mac with a quarantined browser download, including an offline launch using the stapled ticket.

## Explicit preview builds

```sh
RELEASE_CHANNEL=preview VERSION=0.3.14 ./scripts/release.sh
```

This deliberately creates an **unnotarized preview**, which must be labeled as such. Ordinary CI runs tests and `build.sh`; they are not notarized releases. No script publishes automatically.

References: [Apple Developer ID](https://developer.apple.com/developer-id/), [notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution/customizing-the-notarization-workflow), [distribution requirements](https://help.apple.com/xcode/mac/current/en.lproj/dev88332a81e.html).

## View this submission

This is Apple notarization for direct distribution, not an App Store Connect app review. Query the status with the existing local Keychain profile:

```sh
xcrun notarytool info b7fb4e72-7e04-4cc5-9a5f-285974c01ab3 \
  --keychain-profile AutoCorrect-notary

# List this team's submissions:
xcrun notarytool history --keychain-profile AutoCorrect-notary
```

The saved Apple response is `dist/release-0.3.14/notarization/0.3.14-log.json`: status **Accepted**, status summary **Ready for distribution**, issues **null**. No password belongs in these commands. A clean browser download/first launch on another Mac remains a separate release check.
