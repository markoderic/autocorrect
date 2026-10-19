# 0.3.17: leave an unfinished first word alone

October 19, 2026. The owner reported that an initial A disappeared in Claude after a pause, while quickly continuing to type could avoid the problem.

## Finding and fix

The prior automatic path checked an unfinished first word after an 18 ms delay, then capitalized it with backspace/reinsertion. A one-letter field could therefore be deleted before the replacement was delivered. This establishes a risky edit path consistent with the report; it does not independently prove Claude's internal reason for dropping reinsertion. An already-uppercase A did not qualify for that capitalization path.

Automatic mode now leaves the unfinished first word unchanged, including lowercase `a`, uppercase `A`, other letters, leading spaces/brackets and longer unfinished words. Capitalization still runs at a completed-word boundary. An explicit early approval in Ask Before Correcting mode remains possible and retains its undo/casing checks.

Backspace within an unfinished first word retains a bounded count of previously typed characters so completed-word capitalization still works after editing `tex` to `teh`. The strict count for recognizing a completely fresh attempt remains separate: retained text cannot clear manual-rewrite protection. Navigation, focus, completed-word deletion and modified deletion discard this evidence. No key suppression, replay mechanism, timer, model or service was added.

## Verification

- Added two production-engine regressions before the fix: 28 failing assertions. One models an editor losing reinsertion and requires that unfinished text never reach destructive transport. The other covers slow/fast input, a/A, ordinary words, spelling, product casing and following text.
- Added a queue test for retained first-word evidence versus a genuinely fresh attempt. Existing early-edit tests now explicitly approve the early suggestion, preserving their cancellation, verification, casing and Undo assertions. Automatic tests assert delayed capitalization and exact preservation of ignored/mixed-case words.
- Full local suite: **379 executed, 375 passed, four gated audits skipped, zero failures**. Universal arm64/x86_64 build passed.
- **Owner-confirmed physical Claude result on installed 0.3.17:** lowercase `a` and Shift+A both stayed visible after a two-second pause. This closes the reported reproduction, not every Claude editor/Undo/fast-typing path.
- Installed app diagnostics: Accessibility, Input Monitoring, keyboard listener/layout available, login enabled. Settings shows Ready. Existing signing identity and permissions preserved; rollback is `/Applications/AutoCorrect.previous-20261019-140500.app`.

## Distribution

0.3.17 is installed locally. The public download remains the notarized 0.3.16 preview. Release preflight found no Keychain item for `AutoCorrect-notary`, so no new artifact was submitted or published. Restore that credential locally before packaging/submitting a separate Developer ID build. Do not distribute the Apple Development archive as the notarized public download.

Local test/build evidence: `/tmp/autocorrect-initial-before.log`, `/tmp/autocorrect-0317-tests.log`, `/tmp/autocorrect-0317-build.log`, and `/tmp/autocorrect-0317-notarize.log`. No private composer content or credential was captured or committed.
