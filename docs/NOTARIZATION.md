# Warning-free Mac distribution

The current preview is not notarized. “Apple cannot check it for malicious software” means the downloaded build has not passed the Developer ID/notarization distribution path. Installing through Homebrew does not change that fact. The app's Accessibility and Input Monitoring permissions are separate from this first-launch check.

For existing trusted previews, see [Apple's first-open instructions](https://support.apple.com/en-us/102445). Users who do not want to override the warning should wait for a notarized release. Do not disable Gatekeeper or remove quarantine as an installation step.

## Maintainer prerequisites

1. An active Apple Developer Program team and a **Developer ID Application** certificate with its private key in the build Mac's keychain. An **Apple Development** certificate is not interchangeable. The account holder may need to create the Developer ID certificate.
2. An existing `notarytool` keychain profile with authorized notarization credentials. Store credentials interactively with `xcrun notarytool store-credentials`; do not put passwords, private keys, or API keys into this repository or chat.
3. Run the tests before building. Keep the local development signature for local installs so existing Accessibility permission identity remains stable.

On September 29, 2026, the development Mac had only an Apple Development signing identity. There were no repository signing secrets. No notarization submission or successful Gatekeeper assessment is claimed for 0.3.7.

## Current setup — October 12, 2026

The owner reports an existing Apple Developer account with an App Store app. That membership can be used for Developer ID distribution if active and the account has the required Account Holder role. After explicit owner approval, Xcode created **Developer ID Application: Marko Deric (B376DM5LNP)** on October 12. The local signing identity/private key is valid; the existing Apple Development identity is preserved. App Store distribution and Developer ID Application are different certificate types. A separate 0.3.13 build in `dist/developer-id/` is Developer ID signed with hardened runtime and a secure timestamp; its extracted ZIP passes strict signature and both architecture checks. The owner saved the local notarization profile and preflight authentication passed. Apple submission `6be10b1c-e7d6-48d0-abcf-29e29c257104` was uploaded at 23:59 EDT on October 12 and remains **In Progress** at the latest check. It is not yet notarized.

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
VERSION=0.3.13 \
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
NOTARY_PROFILE='your-existing-keychain-profile' \
./scripts/release.sh
```

The stable path checks the installed identity and authenticates credentials before building. The default version comes from `Resources/Info.plist`; `VERSION` can override it. `DIST_DIR` selects the same output folder for build, notarization results, final archive and checksum. Use a separate folder such as `DIST_DIR="$PWD/dist/notarized"` to preserve the local development build. `build.sh` enables hardened runtime and a secure timestamp for Developer ID signatures. `notarize.sh` verifies the signature, stages a copy, submits it to Apple, requires **Accepted**, staples the ticket, and runs Gatekeeper assessment. It then archives and extracts the final download and verifies the extracted app again before replacing the outputs. Rejection leaves the prior bundle/archive untouched. Submission results are in ignored `dist/notarization/`.

Only then update the Homebrew cask with the final ZIP checksum, upload that exact ZIP and checksum to GitHub, and label the release notarized. A checksum from before stapling is not valid for the final artifact. Public first launch still needs validation on a separate Mac with a quarantined browser download, including an offline launch using the stapled ticket.

## Explicit preview builds

```sh
RELEASE_CHANNEL=preview VERSION=0.3.13 ./scripts/release.sh
```

This deliberately creates an **unnotarized preview**, which must be labeled as such. Ordinary CI runs tests and `build.sh`; they are not notarized releases. No script publishes automatically.

References: [Apple Developer ID](https://developer.apple.com/developer-id/), [notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution/customizing-the-notarization-workflow), [distribution requirements](https://help.apple.com/xcode/mac/current/en.lproj/dev88332a81e.html).
