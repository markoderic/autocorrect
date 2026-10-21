# Combined typing follow-up — 0.3.20

October 21, 2026. Starts from `8fe4061aaad0761275db8481f0b06417a30724ec` (0.3.19).

The owner's real-world response combined the requested examples into one message rather than isolated fresh fields. Replaying exactly `It's a problem lets fix this it woks it doest work and helo ` through the 0.3.19 engine returned unchanged. The new regression failed before this fix, reproducing the visible misses without relying on a synthetic foreground keyboard test.

## Why the isolated tests missed it

- `woks`/`doest` required the entire preceding clause to consist of the subject. That missed a later `it` subject in an unpunctuated chat message. Local subject recognition now permits it while excluding object, preposition, naming and quoted-name frames such as `watch it work`, `call it woks`, `called this app woks` and `with this woks`.
- `lets` required an established clause start or invitation continuation. A transitive verb plus an explicit object now supports a later invitation (`lets fix this`) without requiring the missing comma. This does not extend ambiguous objectless `lets go` or noun phrases such as `she lets work pile up`.
- Native en_US ranked `hello` second in isolation but fourth in the combined sentence (`help`, `held`, `halo`, `hello`, `heel`). A four-letter typo's unique single missing double can now appear in the first five guesses, with the existing competing-double, valid-word, casing, structured-text and user-vocabulary gates retained. This replaces the insufficient top-two limit introduced in 0.3.19.

The combined regression now yields:

`It's a problem let's fix this it works it doesn't work and hello `

It also passes through repeated correction cycles with one-character and twelve-character typing chunks. These changes are bounded heuristics, not a general grammar model; they do not claim every run-on sentence can be disambiguated.

## Validation and limits

- Local full suite: **399 executed, 395 passed, four existing optional audit skips, zero failures**.
- Exact combined preview test failed before and passes after. The combined engine/caret fixture, isolated positive examples, valid uses, naming/object/preposition negatives and ignored-word controls pass. The existing first-letter, minimal native edit, Undo and recovery regressions remain green.
- Universal arm64/x86_64 build and strict signature passed. Installed 0.3.20 with the existing Apple Development identity; SHA-256 `add4434d60a34072fdc9bffa595351d862a05344c39277ac7a2e5a146876ae01`; rollback `/Applications/AutoCorrect.previous-20261021-141624.app`.
- Normal startup with tracing off; Settings Ready / both permissions Allowed. Installed diagnostics: permissions, listener creation and supported layout true, login enabled. Exact combined-sentence physical retest requested, pending. This remains distinct from engine/native-event simulation.
- Runtime `bb33c556e94ceca51bc9307c111738e4d2ae61b3` pushed; [hosted CI 39651368819](https://github.com/markoderic/autocorrect/actions/runs/39651368819) passed tests, release-script checks, universal build and archive upload. This CI archive is not the public notarized release. Latest physical retest had no reply at task close; do not convert the earlier failed combined test into a pass.
- Public remains notarized 0.3.16. Missing local `AutoCorrect-notary` credentials still block a new notarized public download; no new submission or upload.

## Owner physical confirmation

Later on October 21, the owner replied to the exact combined-sentence retest with:

`It's a problem let's fix this it works it doesn't work and hello`

They explicitly confirmed every example now works. This closes this reported combined-sentence regression with user-reported physical evidence in addition to the automated tests. The reply did not restate the host app; it does not establish separate passes in multiple apps, long-duration listener reliability or general 1.0 readiness. The earlier failed 0.3.19 result remains part of the history. No runtime change or new installation was needed for this confirmation.
