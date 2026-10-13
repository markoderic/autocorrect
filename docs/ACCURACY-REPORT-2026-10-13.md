# Current accuracy failure report — AutoCorrect 0.3.13

Tested October 13, 2026 on macOS 27.0.1, Apple M5 Pro. Runtime source `ac41af5`; checkout `0eb76c4` includes documentation-only follow-ups. **No production code, repository tests, settings or installed-app changes.** Tests ran against a temporary source snapshot; every Swift source hash matches the checkout. Outputs are in [the dated results folder](../evaluation/results/2026-10-13-current-0313/).

## Assessment

The largest blockers are **harmful automatic replacements**, **unreliable sentence suggestions**, and **very limited punctuation coverage**. Broadening automatic correction before addressing false replacements would increase the chance of changing the writer's meaning. The current app is not yet supported by enough accuracy and real-typing evidence for 1.0.

This is a current run of existing, previously inspected benchmark data, not a new independent held-out assessment or a percentage of all English writing. The scorer's historic `dev`/`held` labels are retained for comparison only. Automatic spelling and optional sentence suggestions are measured separately; their scores cannot be added to claim combined end-to-end accuracy.

## Biggest problems, ordered for the next implementation round

| Priority | Problem | Current observed example | Intended result / significance |
| --- | --- | --- | --- |
| 1 | Wrong automatic candidate selection | `Call me bedore you leave the office.` → `Call me bedsore you leave the office.` | `before`. The engine sometimes favors a candidate that preserves typed letters over a better native recommendation. |
| 1 | Changes to valid names and spellings | `Ngozi` → `Ngoni`; `organise` → `organisae` | Preserve both. Names and valid regional spellings need stronger protection. |
| 2 | Invalid sentence suggestions survive validation | `This coffee is more better…` → `This coffee is more gooder…` | `This coffee is better…`. Occurred in two of three sampled model runs. These suggestions require user approval; they are not automatic edits. |
| 2 | Quoted text is not reliably protected | `He texted "ur late lol"…` → `He texted "you late lol"…` | Preserve the quote. Happened in all three sampled runs. |
| 2 | Exact error messages are rewritten | `"cannot find module 'react'"` → `"couldn't find module 'react'"` | Preserve the exact error string. All three runs rewrote it, using different alternatives. |
| 3 | Weak sentence-context ranking | `I fell asleep on the chuch…` → `…on the church…`; `The total caost…` → `The total coast…` | `couch` and `cost`. Immediate word correction does not consistently resolve ambiguity from surrounding meaning. |
| 3 | Real-word errors remain unchanged | `They left there bags…`, `We can't afford to loose this customer.` | `their`, `lose`. These are missed by the automatic word path; valid dictionary words require context. |
| 4 | Punctuation coverage is poor | Run-ons, commas and several apostrophe errors stay unfixed | Sentence suggestions fixed 2 of 42 labeled punctuation errors in eligible items in this run. |

Other current automatic failures: `devided → decided` instead of `divided`; `lastr → laster` instead of `last`; `whant → what` in “Do you whant pizza…”; `adquiring → awdquiring` even though the native recommendation was `acquiring`.

One separate preference issue: `omw → On my way` is the existing default abbreviation feature, not an unintended engine regression. It counts as a mismatch when a fixture explicitly asks to retain informal wording. Do not group it with name corruption when choosing fixes.

## Measurements

### Automatic spelling benchmark

4,304 misspelling entries assessed in two contexts, plus 2,928 corpus-labeled correct-word controls: **11,536 assessments**. Report one context below to avoid counting the same typo twice.

| Isolated-word outcome | Count |
| --- | ---: |
| Single-target misspellings | 4,097 |
| Exact expected correction | 3,522 |
| Case-only match | 1 |
| Scorer-recognized US spelling variant | 14 |
| No automatic correction | 376 |
| Wrong target replacement | 184 |
| Ambiguous entries, assessed separately | 207 |
| Ambiguous: abstained / chose listed target / chose unlisted target | 31 / 158 / 18 |

After `please check`, the same 4,097 single-target entries produced 3,521 exact matches, 1 case-only match, 14 US variants, 382 misses and 179 wrong target replacements. Context changes a few decisions but does not resolve the larger ranking problem.

Of 2,928 correct-word controls, 30 were changed. Many are routine en_US normalization of British forms and one is `youtube → YouTube`; the control list also includes rare/questionable dictionary entries. **Do not describe all 30 as harmful corruption.** Confirmed concerning examples include `organise → organisae`, `hydrophobe → hydrophone`, and `hydrophile → hydrophily`.

The isolated single-target misses break down as follows: 71 dictionary-accepted misspellings, 55 flagged without a native automatic recommendation, 122 policy refusals with the expected word ranked first, 74 refusals with it ranked 2–5, and 54 with it absent from the first five guesses. This is why fixing misses requires different approaches rather than one looser confidence threshold.

Evidence: [spelling report](../evaluation/results/2026-10-13-current-0313/spelling-report.md), [native signals and outcomes](../evaluation/results/2026-10-13-current-0313/spelling-observations.json).

### Authored contextual and correct-text fixtures

The automatic engine ran 207 fixtures through its preview/completed-word path using throwaway default preferences.

- **40 contextual spelling cases:** 17 correct replacements, 4 appropriate abstentions, 10 missed corrections, 9 wrong replacements.
- **60 correct/informal texts:** 3 changed contrary to fixture intent: the name example, the British spelling sentence, and the deliberate `omw` abbreviation. Two are harmful failures; one is the default expansion policy.
- **7 typing fixtures:** 7 matched documented current behavior. Some fixtures intentionally expect no correction before a delimiter; this is not seven successful typo repairs or physical typing evidence.
- Automatic grammar/punctuation scores appear in the raw tables for completeness, but the optional sentence analyzer below is the relevant separate subsystem for those tasks.

Evidence: [automatic tables](../evaluation/results/2026-10-13-current-0313/automatic/scores.md), [per-item results](../evaluation/results/2026-10-13-current-0313/automatic/per_item.csv).

### Production sentence analyzer and validator

Ran the current production `SentenceAnalyzers.preferred()` and `SuggestionValidator` with both grammar and punctuation enabled. This Mac used **Apple Intelligence's on-device model**. Each fixture was evaluated as a complete sentence or paused clause, with a fresh model session. Model outputs were captured before and after validation.

| Category | Evaluated items | Labeled errors | Correct fixes | Wrong labeled fixes | Misses | Additional unwanted edits |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Grammar | 59 | 65 | 17 | 3 | 45 | 3 |
| Punctuation | 35 | 42 | 2 | 3 | 37 | 0 |
| Correct/informal controls | 52 | — | — | — | — | 3 changed items |

No analyzer errors occurred in the 146 evaluated items. Of 55 raw proposed edits, 31 passed validation. Median analyzer time was about 477 ms, p95 about 1,266 ms; this is inference time, not physical correction latency.

**Coverage caveat:** the audit skipped 14 of the 160 fixtures because the full text was not one eligible unit: 1 grammar item/1 labeled error, 5 punctuation items/5 errors, and 8 controls. Several contain multiple sentences, line breaks or abbreviations such as `Dr.`. The raw scorer retains these as unchanged; the table above removes skipped errors from the miss count. A skipped multi-sentence fixture is not proof that the live app would never review its component sentences.

**Delivery caveat:** these are suggestions that passed the validator before additional UI/edit-transport checks. The diagnostic output shows the result if all returned suggestions were accepted. It does not mean that the app applied them automatically or that every proposal would successfully apply in a real editor. Inputs were not first rewritten by the automatic spelling path, so these are separate subsystem diagnostics.

Other manually reviewed bad proposals:

- `Each of the students have a laptop.` → `Every of the students have a laptop.`
- `Between you and I, the demo was a mess.` → `Between you, the demo was a disaster.`
- `Your going to need a jacket…` → `You going to need a jacket…`.
- A run-on beginning `We got there late the show had already started…` lost `the show` instead of gaining punctuation.

The validator protects several token classes but does not establish grammatical correctness or preserved meaning. Ordinary quoted spans are not categorically protected. Its requirement that edit spans and replacements begin/end with letters also rejects some punctuation edits. That restriction is tied to edit transport, so relaxing it blindly would be unsafe. Both model coverage and transport-compatible punctuation proposals need investigation.

Evidence: [sentence outputs](../evaluation/results/2026-10-13-current-0313/production-sentence.jsonl), [sentence tables](../evaluation/results/2026-10-13-current-0313/sentence/scores.md), [measurement-only test](../evaluation/results/2026-10-13-current-0313/measurement-only/CurrentSentenceAuditTests.swift).

### Variability check

Repeated seven problematic fixtures twice more without changing prompts or production code. This is a diagnostic probe, not another unbiased sample.

- “More better” → “more gooder” occurred **2/3** times; the remaining run correctly removed “more.”
- `"ur late lol"` was changed to `"you late lol"` in **3/3** runs.
- The exact error message was changed in **3/3** runs, to `couldn't`, `could not`, or `can't`.
- Other examples alternated among no suggestion, a useful partial correction and a malformed rewrite. One retry changed the distributive-subject example to `Each student has have a laptop.`

Evidence: [repeat 2](../evaluation/results/2026-10-13-current-0313/sentence-stability-2.jsonl), [repeat 3](../evaluation/results/2026-10-13-current-0313/sentence-stability-3.jsonl).

## Proposed work toward 1.0 — not implemented

1. **Stop harmful automatic replacements:** protect names and valid regional spellings; revisit the letter-preserving-candidate preference using positive and negative cases. Track any increase in missed corrections alongside the reduction in wrong replacements.
2. **Make sentence suggestions trustworthy:** protect quoted/error text, reject unjustified wording/tense changes, and improve grammatical validity checks. Keep these changes reviewable; current evidence does not justify automatic sentence rewriting.
3. **Improve contextual word choice:** evaluate ambiguous candidates in sentence context and abstain or suggest when intent remains unclear. Preserve the speed of clear spelling repairs.
4. **Address punctuation as a separate feature:** measure model misses, sentence segmentation and validator/edit-transport refusals separately. Design safe punctuation edits before changing the guards.
5. **Run fresh acceptance data and real typing:** freeze unseen examples before tuning, repeat on another supported macOS version, and verify typing/Undo/focus/text preservation in native and browser editors. No current report substitutes for those release gates.

Do not pick one overall accuracy percentage as the release gate. Require separate evidence for wrong automatic changes, missed corrections, valid-text preservation, suggestion quality and real-editor text integrity.

## Apple notarization status

**Accepted.** Submitted via Apple's `notarytool` service for direct Mac distribution, not App Store Connect App Review. Submission ID: `6be10b1c-e7d6-48d0-abcf-29e29c257104`. Apple's downloaded log says **Ready for distribution**, with no listed issues.

The prior waiting process had ended before completing local packaging. Recovered the existing accepted submission without re-uploading. Stapled/validated the ticket, then verified the final extracted ZIP with strict codesign, both architectures, Gatekeeper (`Notarized Developer ID`) and `syspolicy_check distribution`; all passed.

The notarized ZIP is local at `dist/developer-id/AutoCorrect-0.3.13-universal.zip`, SHA-256 `c32de5d913d15334554d36a8a2a03882375f536c3e4a337bf08b4a72c938b934`. Public v0.3.7 and the installed development build remain unchanged. A quarantined browser download and first launch on another Mac remain untested.

View the saved [Apple log](../dist/developer-id/notarization/0.3.13-log.json), or query live status:

```sh
xcrun notarytool info 6be10b1c-e7d6-48d0-abcf-29e29c257104 \
  --keychain-profile AutoCorrect-notary
```

List submissions with `xcrun notarytool history --keychain-profile AutoCorrect-notary`. [Apple's workflow documentation](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
