# Held-out accuracy evaluation

This directory holds a pinned public corpus and the latest report produced by
`AccuracyEvaluationTests` (in `Tests/AutoCorrectTests/`). It is separate from
the hand-labeled regression fixtures used for tuning.

## Corpus

- `wikipedia-common-misspellings.txt`: the raw wikitext of
  [Wikipedia:Lists of common misspellings/For machines](https://en.wikipedia.org/wiki/Wikipedia:Lists_of_common_misspellings/For_machines),
  revision **1199637275** (2024-01-27T15:31:36Z), fetched 2026-09-30.
  Format: `misspelling->correction[, alternative]`. Entries with several
  corrections are ambiguous; abstaining is the correct decision for them.
- License: Wikipedia text is available under the
  [Creative Commons Attribution-ShareAlike 4.0 License](https://creativecommons.org/licenses/by-sa/4.0/).
  The file is an evaluation fixture only; nothing from it is bundled in the app.
- The corpus is Wikipedia-editor authored, skewed toward encyclopedic
  vocabulary, and contains no casing, spacing, or sentence-boundary cases and
  few chat-style abbreviations. It is not a sample of Marko's typing.

## Partitions

Entries alternate between a **development** half (even lines, which may inform
policy changes) and a **held-out** half (odd lines, reported but never used to
tune rules). Compare the held-out numbers across versions and hosts.

## Running

```sh
AUTOCORRECT_EVALUATION=1 swift test --build-system native --filter AccuracyEvaluationTests
```

The test is skipped without the environment variable. It queries the actual
`NSSpellChecker` on the host, so results depend on the macOS version; the report
records the OS. It writes `evaluation/latest-report.md` and prints a summary.

## Reading the report

- **correct**: the engine's automatic replacement equals the expected word.
- **missed**: no automatic replacement. Broken down by native signal: the
  dictionary accepted the misspelling, no automatic recommendation, or the
  policy declined (with the rank of the expected word among native guesses).
- **false correction**: an automatic replacement that is not the expected word.
  This is the number that matters most; each one is listed.
- **ambiguous**: entries with several corrections. Abstaining is correct;
  choosing one of the listed corrections is acceptable; anything else is a
  false correction.
- **controls**: every distinct single-word correction from the corpus, typed
  correctly. Any change is a false correction of a valid word.

Do not describe these counts as English accuracy. They measure one corpus on one
host through the same completed-word path the keyboard uses, without keyboard
events or Accessibility.
