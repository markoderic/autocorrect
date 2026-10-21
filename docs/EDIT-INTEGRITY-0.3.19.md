# Editing integrity and reported omissions — 0.3.19

October 21, 2026. Starts from recovery runtime `9f573040c3d4667f24e04794b7f42e5678381859`; its [hosted CI 39649086013](https://github.com/markoderic/autocorrect/actions/runs/39649086013) passed. The owner confirmed corrections were working again after 0.3.18, then reported Claude losing the initial letter around `its` and missed `helo`, `woks`, `doest`, `its` and `lets` repairs.

## Findings and change

The old native event sequence deleted the whole correction span plus its following text, then inserted the replacement and following text. At the beginning of a composer, this temporarily cleared the entire field—even for a completed word. Four new decoded-event regressions failed the never-empty assertion before the change. This is a demonstrated hazardous sequence; the exact physical `its` → `t’s` event was not captured, so it is not proof of that report's sole cause.

The replacement plan now computes a minimal changed span. Native events move the caret left over the unchanged suffix, change only the differing characters, and move right to the original logical caret position. Unchanged prefix/suffix text stays in the host; completed-first-word corrections never clear the composer. No temporary selection, clipboard operation or synthetic submit occurs. Event batches retain the existing validation, injection marker, ordering and no-replay guarantees. All old length, character, focus, stale-snapshot and replacement gates still apply. Explicitly approved unfinished-word edits remain separate from automatic completed-word corrections.

The dictionary probes also showed:

- `helo`: macOS en_US calls it misspelled but ranks `help` above `hello`. The existing repeated-consonant rule started at five letters. Four-letter forms now qualify only for a unique single missing doubled consonant ranked in the first two guesses. Other ranked double repairs block ambiguity; names, acronyms, valid words and ignored words retain their guards. This is a general extension, also tested with `hapy` and `sily`.
- `woks`: a valid plural noun, so it is preserved alone and in `two woks`. A bounded completed singular-subject frame permits an omitted letter in `works`, e.g. `it woks` or `the app woks`. Valid `work` is excluded from this repair.
- `doest`: accepted as an archaic word. The reported `doesn't` reading is permitted only after a modern singular subject and before a completed base verb, e.g. `it doest work`. Standalone `doest`, archaic `thou doest work`, valid `does`, ignored words and custom replacements retain priority. This is a deliberately limited heuristic, not general semantic inference.
- `its a problem`, `lets fix this` and `its working now` already produced the right contextual candidates in the old engine. The follow-up tests cover them through slow and fast first-word capitalization sequences and through decoded native edits. Isolated `its`/`lets` still wait for disambiguating context; possessive and ordinary verb uses remain intact.

## Validation

- Before: two new tests failed five assertions (four field-clearing paths and missed `helo`). Fixed-string native probes additionally recorded missed `it woks`, `the app woks` and `it doest work`.
- After: full local suite **397 executed, 393 passed, four existing optional audit skips, zero failures** on macOS 27.0.1. Native event tests verify exact text/caret, balanced tagged events, Unicode insertions, long suffixes, contraction Undo and nonempty completed first words. AppKit labels arrow keycodes with its function-key modifier during conversion; tests distinguish this from actual Shift/Control/Option/Command modifiers.
- Reported-typing fixtures cover eleven positive word/phrase outcomes, ten valid/structured negatives and five ignored-word controls. Slow/fast engine sequences cover six full phrases in each mode. These are regression fixtures, not a fresh general-English accuracy benchmark.
- Universal arm64/x86_64 release compilation and strict signature passed. Intel runtime and long-duration resource behavior remain untested.
- Installed 0.3.19 with the existing Apple Development identity. Executable SHA-256 `80de51f38d0c61c813ec4fd7fb756c363d65bb44169b0b1adf2f0dc1e76bf5cc`; rollback `/Applications/AutoCorrect.previous-20261021-140839.app`.
- Normal startup with tracing off; Settings Ready, permissions Allowed; diagnostics reports both permissions/listener creation/layout and login enabled. Physical Claude test of five phrases requested; result pending. Native-event decoding and simulated host edits are not physical-keyboard passes.

## Release boundary

Installed development build only. Public remains the notarized 0.3.16; the October 21 notarization preflight still cannot find `AutoCorrect-notary`. No new Apple submission or public binary upload occurred. Original intermittent stop trigger, sustained recovery and wider editor/caret/Undo behavior remain acceptance items before 1.0.

## Physical follow-up

The owner subsequently typed the combined sequence in this chat and reported remaining misses: `It's a problem lets fix this it woks it doest work and helo`. Treat that as a failed real-world acceptance check, not confirmation of the isolated fixtures. The same sequence reproduced all four misses in the 0.3.19 engine: its context guards required a clause start, and the native ranking for `hello` moved to fourth place. Follow-up work is recorded in [0.3.20](COMBINED-TYPING-0.3.20.md). Runtime `8fe4061aaad0761275db8481f0b06417a30724ec` passed [CI 39650331851](https://github.com/markoderic/autocorrect/actions/runs/39650331851); that green CI did not establish physical acceptance.
