# AutoCorrect 0.3.14 — measured accuracy repairs

October 13, 2026. Comparison against 0.3.13 on macOS 27.0.1 (26A434), Apple M5 Pro. This is a notarized preview, not 1.0 acceptance.

## Results and tradeoffs

| Measure | Before | After |
| --- | ---: | ---: |
| Wrong automatic replacements / 4,097 single-target misspellings | 186 | 96 |
| Exact automatic repairs / 4,097 | 3,521 | 3,400 |
| Missed automatic repairs / 4,097 | 375 | 586 |
| Other accepted outcomes (case-only / US variants) | 1 / 14 | 1 / 14 |
| Corpus-labeled valid words changed / 2,928 | 30 | 9 |
| Wrong contextual choices / 40 authored spelling cases | 9 | 2 |
| Correct contextual replacements / 40 | 17 | 14 |
| Appropriate abstentions / 40 | 4 | 5 |
| Missed contextual corrections / 40 | 10 | 19 |
| Correct grammar fixes / 65 eligible labeled errors | 17 | 26 |
| Incorrect or incomplete labeled grammar fixes | 3 | 1 |
| Additional unwanted grammar edits | 3 | 0 |
| Correct punctuation fixes / 42 eligible labeled errors | 2 | 10 |
| Wrong labeled punctuation fixes | 3 | 0 |
| Sentence suggestions changing correct/informal controls / 52 eligible | 3 | 0 |

Wrong automatic replacements fell **48.4%** (90 fewer), with **121 fewer exact automatic repairs** and **211 more misses**. This intentionally prefers leaving ambiguous text alone to silently selecting the wrong word. It is not an unqualified coverage improvement. Review/indication remains available for uncertain words under the user's existing settings.

The initial failure report had 184 wrong replacements and 3,522 exact repairs. A fresh run of the unchanged baseline produced 186 and 3,521; the table uses that fresh rerun because native dictionary behavior can vary. The remaining spelling outcomes still sum to 4,097. The 207 ambiguous entries are separate: listed choice / abstention / unlisted choice changed from 158/31/18 to 143/53/11.

Thirty changed controls were not all harmful: many were regional spelling normalization. Nine remaining changes include `youtube → YouTube`, questionable/rare corpus entries, and unresolved harmful cases `hydrophobe → hydrophone` and `hydrophile → hydrophily`. Do not present the control count as nine confirmed corruptions or zero remaining harm.

## What changed

- **Competing spellings require stronger evidence.** A native substitution/deletion with an equally close competitor, or a conflicting letter-preserving guess, can be kept for review. Established short missing-vowel, transposition, doubled-letter, and past-participle repairs remain supported. `bedore`, `adquiring`, `lastr`, `devided`, and `whant` no longer receive their previous harmful replacements on this host. Several now abstain rather than produce the intended correction.
- **Names and regional spelling are safer.** Unknown title-cased tokens inside prose are not silently replaced with other names. English words accepted by the other regional dictionary are preserved. Explicit user replacements and ignored words remain authoritative. `Ngozi` and `organise` are preserved.
- **Curated product repair handles unreliable native competitors.** On this host even the unchanged baseline offered `gxthbu` for `githbu`. Unique curated product candidates now cross-check ordinary-word competitors in the second English dictionary. The existing `githbu → GitHub` regression passes again; ordinary valid words and the product-casing toggle remain protected.
- **Grammar has deterministic rules before model proposals.** Narrow agreement, duplicated function-word, modal `of/have`, comparative and pronoun rules produce reviewable edits. `Each of the students have` becomes `Each of the students has`; `more better` becomes `better`; `Between you and I` becomes `Between you and me` without changing “mess” to “disaster.”
- **Model suggestions preserve vocabulary and quotations.** Straight, curly, single and unfinished quotes are protected. Guards reject arbitrary paraphrases, dropped subjects, invalid word substitutions, unnecessary capitalization, and possessive `its → it's` without contextual evidence. Greedy sampling reduces sampling variation but is not a promise of determinism across OS/model updates.
- **Punctuation uses safe anchors.** Missing contraction apostrophes and interior punctuation spacing can be suggested. A punctuation span can include an unchanged adjacent word so it fits the existing keyboard replacement contract. Final punctuation with no safe anchor is still unsupported; the transport was not loosened.

## Verification

- Full Swift suite: **368 executed, 365 passed, three gated evaluations skipped, zero failures**. Spelling and sentence audits were also run explicitly and passed as measurements, not accuracy-threshold tests.
- Release orchestration: **6 passed**. Benchmark scorer: **25 passed**.
- Fallback build with `NO_FOUNDATION_MODELS`: passed. Release builds: arm64 and x86_64, passed.
- New tests cover quotation protection, malformed proposals, unrelated rule examples, correct-text controls, native name/dialect preservation, preference precedence, ambiguity policies, and punctuation edit/Undo plans retaining following text.
- Native integration tests now explicitly permit abstention for ambiguous cases rather than demanding an unsafe automatic choice. Deterministic core tests pin the actual conflict rules; normal typo regression assertions remain strict.
- Installed 0.3.14 with the existing development identity and a rollback copy. Diagnostics show Accessibility/Input Monitoring/listener/layout available and login enabled. Settings shows Ready. Installed preview preserves `Dr. Ngozi can organise this`, defers `bedore`, and still repairs `teh quick brown fox`; disposable input was cleared.
- These are engine, edit-plan and settings-preview checks. **Physical keyboard, real-editor Apply/Undo, another Mac, Intel runtime and sustained resource behavior remain unverified.**

## Evaluation boundaries and reproducibility

The spelling audit uses 4,304 pinned public misspellings in two contexts plus 2,928 controls (11,536 assessments). The table reports one context to avoid duplicating typos. Both contexts and native signals are saved locally.

The sentence audit evaluates 146 of 160 fixtures: 59 grammar, 35 punctuation and 52 correct/informal. Fourteen multi-unit fixtures remain skipped, exactly as in the baseline. Raw score tables include them as unchanged; the table above excludes their one grammar and five punctuation labels. The final run correctly fixed 26 grammar errors, left 38, and made one incomplete repair (`Theres two seats → There's two seats`, still missing plural agreement). Punctuation fixed 10 and left 32. Sentence inference median was about 470 ms and p95 about 1.13 seconds; this is not keyboard latency.

The model and automatic paths are evaluated separately; their scores cannot be added into an end-to-end accuracy claim. All these examples were already inspected during development, including historical “held” partitions. They are regression/tuning data, not fresh held-out proof of English accuracy. No network model, corpus download or typing-history collection was added.

The seven previously worst sentence fixtures were rechecked: malformed rewrites and quote/error-message changes were prevented; the unresolved run-on was left unchanged. Quote protection has deterministic regression coverage as well as observed model results.

Local evidence directory: `evaluation/results/2026-10-13-repairs-0314/`. It contains the baseline rerun, final spelling observations/report, 207 automatic fixtures, sentence raw/validated proposals, scorer tables, a stability check and runtime source hashes. Abandoned ranking trials are retained there; the first increased wrong corrections and was not shipped. The gated `CurrentSentenceAuditTests` accepts `AUDIT_CORPUS` and `AUDIT_OUTPUT` paths for reproduction without touching app preferences.

## Distribution

Developer ID Application signing, hardened runtime, secure timestamp and notarization completed. Apple submission `b7fb4e72-7e04-4cc5-9a5f-285974c01ab3`: **Accepted**. Ticket stapled and validated; the final extracted ZIP passed strict codesign, both architectures and Gatekeeper (`Notarized Developer ID`). `syspolicy_check distribution` also passed.

Final public artifact: `AutoCorrect-0.3.14-universal.zip`.
SHA-256: `5aaadc913aa7c050683d1d5943944c1a4de5ed0fd572756841381cdbfec51898`.

Published as [v0.3.14](https://github.com/markoderic/autocorrect/releases/tag/v0.3.14), targeting runtime `ab5d4b2`. [Hosted macOS 14 CI](https://github.com/markoderic/autocorrect/actions/runs/38404451088) passed. A fresh public browser download matched the ZIP checksum. Browser quarantine was retained and propagated unchanged to the extracted test app; strict signature, both architectures, stapled ticket, Gatekeeper and distribution checks all passed. This is same-host assessment, not another-Mac first-launch evidence. The installed development signature is kept separate to preserve existing permissions; only the Developer ID notarized archive is intended for public download. No Gatekeeper bypass or customer quarantine removal is part of this release. Another Mac's quarantined browser download/first launch remains a required follow-up.

Next priorities toward 1.0: recover safe contextual coverage without increasing wrong replacements, protect rare valid vocabulary, improve subject/verb and punctuation coverage (including final punctuation transport), freeze fresh independently labeled cases, and complete actual typing/Undo/focus and clean-Mac download acceptance.
