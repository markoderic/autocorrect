# Warning-free Mac distribution

The current preview is not notarized. “Apple cannot check it for malicious software” means the downloaded build has not passed the Developer ID/notarization distribution path. Installing through Homebrew does not change that fact. The app's Accessibility and Input Monitoring permissions are separate from this first-launch check.

For existing trusted previews, see [Apple's first-open instructions](https://support.apple.com/en-us/102445). Users who do not want to override the warning should wait for a notarized release. Do not disable Gatekeeper or remove quarantine as an installation step.

## Maintainer prerequisites

1. An active Apple Developer Program team and a **Developer ID Application** certificate with its private key in the build Mac's keychain. An **Apple Development** certificate is not interchangeable. The account holder may need to create the Developer ID certificate.
2. An existing `notarytool` keychain profile with authorized notarization credentials. Store credentials interactively with `xcrun notarytool store-credentials`; do not put passwords, private keys, or API keys into this repository or chat.
3. Run the tests before building. Keep the local development signature for local installs so existing Accessibility permission identity remains stable.

On September 29, 2026, the development Mac had only an Apple Development signing identity. There were no repository signing secrets. No notarization submission or successful Gatekeeper assessment is claimed for 0.3.7.

## Build a notarized release

```sh
swift test --build-system native
VERSION=0.3.9 \
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
NOTARY_PROFILE='your-existing-keychain-profile' \
./scripts/release.sh
```

The stable path requires the correct identity and credentials before building. `build.sh` enables hardened runtime and a secure timestamp for Developer ID signatures. `notarize.sh` verifies the signature, stages a copy, submits it to Apple, requires **Accepted**, staples the ticket, and runs Gatekeeper assessment. It then archives and extracts the final download and verifies the extracted app again before replacing the outputs. Rejection leaves the prior bundle/archive untouched. Submission results are in ignored `dist/notarization/`.

Only then update the Homebrew cask with the final ZIP checksum, upload that exact ZIP and checksum to GitHub, and label the release notarized. A checksum from before stapling is not valid for the final artifact. Public first launch still needs validation on a separate Mac with a quarantined browser download, including an offline launch using the stapled ticket.

## Explicit preview builds

```sh
RELEASE_CHANNEL=preview VERSION=0.3.9 ./scripts/release.sh
```

This deliberately creates an **unnotarized preview**, which must be labeled as such. Ordinary CI runs tests and `build.sh`; they are not notarized releases. No script publishes automatically.

References: [Apple Developer ID](https://developer.apple.com/developer-id/), [notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution/customizing-the-notarization-workflow), [distribution requirements](https://help.apple.com/xcode/mac/current/en.lproj/dev88332a81e.html).
