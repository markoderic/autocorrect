# Context, macOS compatibility, and undo

Research checked September 29, 2026. This memo separates API guarantees from implementation recommendations. The app uses local processing; these research requests contained API names and public examples, never editor content.

## Small contextual rules

`ContextualWritingRules.candidate(in:)` returns one candidate with a UTF-16 range, original word, replacement, explanation, and explicit automatic eligibility. The caller supplies at most 256 UTF-16 units of completed text before the caret. The helper examines up to three following completed words, requires ordinary spaces between them, and preserves initial capitalization. It does not activate itself, change an editor, or decide whether a language or setting is enabled.

Supported examples include `its a`, `its been`, `its not`, `its going to`, sentence-initial `lets build` / `lets all go`, and possession contexts such as `check it's color` or `it's color is`. Correct `its color`, `it's raining`, `she lets go`, and `the app lets users` are untouched. Bare `it's color` waits: `it's color, not shape` can be correct. `its going rate` is also left alone. These finite patterns are not a complete grammar model; wording, quotations, specialist usage, and truncated context can still be ambiguous. Since 0.3.2, clearer contraction/invitation patterns and a possessive followed by a predicate can apply automatically. The global approval setting still wins; weaker possessive cues require review. Adjectives wait for a complement or sentence punctuation, so `its good looks` and `its working parts` survive. Subject-position checks protect possessive gerunds such as `despite its not working`.

LanguageTool's public English [rule source](https://github.com/languagetool-org/languagetool/blob/master/languagetool-language-modules/en/src/main/resources/org/languagetool/rules/en/grammar.xml) demonstrates why context matters: `LETS_LET` uses grammatical tags and exceptions; `ITS_TO_IT_S` excludes noun/adjective contexts; a broader possessive rule `ITS_JJ_NNSNN` is disabled with a false-positive comment. This implementation is independently written and does not copy or bundle those rules. Its smaller scope is deliberate.

## Other local language engines

Apple's [NSSpellChecker background checking API](https://developer.apple.com/documentation/appkit/nsspellchecker/requestchecking(of:range:types:options:inspelldocumentwithtag:completionhandler:)) can request grammar checks as well as spelling. It returns a sequence number; completion occurs in an arbitrary context. A future adapter should check a bounded sentence after a pause, discard stale results, return to the main thread, and request approval. The API is an attractive system-provided backend, but its documentation does not promise detection of every grammar error or identical results across OS versions. Native API availability alone also does not establish the privacy behavior of every separately installed spelling service.

Apple [NaturalLanguage lexical tags](https://developer.apple.com/documentation/naturallanguage/nltagscheme/lexicalclass) classify nouns, verbs, and other parts of speech. They could refine a rule but do not directly provide grammar corrections. The present finite rules add no model download, background server, or network request and run only when requested on a completed word.

A local LanguageTool server would provide broader rules, but its [Java embedding documentation](https://dev.languagetool.org/java-api) requires Java 17 for current versions. Its [server guide](https://dev.languagetool.org/http-server) describes a separate runtime and optional language-identification model; cloud-only AI rules are excluded from that local server. That added runtime is a poor default for this small utility. A bundled local language model would also need measured storage, memory, latency, and accuracy before adoption. Neither alternative fixes editor compatibility. No such engine is bundled or called here.

## Why support cannot be universal

- Accessibility text/caret attributes depend on the target application. Apple's [AX attribute API](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue) can report unsupported attributes or failed communication. Missing or stale readable text must prevent an edit; blind keystroke buffering is not a substitute.
- Electron documents [AXManualAccessibility](https://www.electronjs.org/docs/latest/tutorial/accessibility) for third-party accessibility clients. Enabling a tree helps supported Electron editors expose text; it does not guarantee every custom editor supplies usable ranges. Electron also warns that [enabling accessibility affects performance](https://www.electronjs.org/docs/latest/api/app#appsetaccessibilitysupportenabledenabled), so repeated enabling and broad polling are inappropriate.
- Apple's [Secure Event Input note](https://developer.apple.com/library/archive/technotes/tn2150/_index.html) explains that protected entry blocks keyboard interception. The app should continue to skip secure fields and respect that boundary.
- Apple's [Unicode keyboard-event documentation](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring(stringlength:unicodestring:)) explicitly allows application frameworks to ignore an event's Unicode string. Its [tap posting API](https://developer.apple.com/documentation/coregraphics/cgevent/tappostevent(_:)) orders inserted events before the callback's returned event, but does not promise atomic edits inside the destination application. Input-method composition and custom editors therefore require separate compatibility checks, not a universal-support claim.

## Safe undo design

Apple's [UndoManager](https://developer.apple.com/documentation/foundation/undomanager) records operations owned by an application. An external utility cannot assume another app grouped generated deletes and inserts as one undo operation. Sending Command-Z may remove unrelated typing; using AX to restore an entire field may overwrite newer content.

Implemented explicit “Undo last correction”: retain one verified, in-memory record for up to five minutes. Store the process/field identity, absolute replacement range, replacement text, and up to 32 UTF-16 units of preceding context. Fresh text must match that exact anchor in the same focused field; no text search or caret guess is used. Continued typing is allowed when the saved anchor remains in the 256-unit snapshot and the following ASCII text is at most 96 units. Revalidate the full fresh snapshot again at event delivery. A canceled inverse keeps its record; a posted inverse consumes it even if verification fails, preventing a second destructive attempt. The app uses Control–Option–Command–Z and does not intercept the host’s Command–Z.

A separate session epoch invalidates callbacks after focus, mouse, navigation, or settings changes. Ordinary continued typing preserves the session. A bounded boundary queue stores offsets rather than raw keystrokes and retries stale reads at most three times. Failed post-edit verification never repeats a deletion. These are bounded safeguards, not a guarantee that another process accepts every generated event.

These checks reduce stale edits but cannot create an OS-level transaction with another process. Tests of pure rules and event construction are necessary; they do not establish real application delivery, host undo grouping, or typing-race safety. Those require unsubmitted editor fixtures and explicit observed results per app and version.


## Broader spelling without a bundled model

[Norvig’s spelling-correction discussion](https://norvig.com/spell-correct.html) distinguishes edit distance from the language/error probabilities needed to choose candidates. [SymSpell’s implementation](https://github.com/wolfgarbe/SymSpell) combines distance and frequency ordering. This app adds neither library nor dictionary download: it keeps macOS’s native ranking and applies small acceptance gates.

A first-ranked native guess can qualify with one edit for words of five or more letters. For words of eight or more letters, two edits can qualify when first/last letters match and distance is no more than one quarter of the source length. A native-recommended two-edit candidate among the first three guesses can also qualify when strictly closer than every alternative among the first five. Equal or closer competing candidates prevent this fallback. Tests cover reordered native guesses for `capitazed`, since isolated and sentence contexts can rank `captioned` and `capitalized` differently. These are heuristics, not calibrated confidence scores or a measured everyday accuracy percentage.


## 0.3.2 accuracy investigation

The native spell checker receives the bounded surrounding text and target UTF-16 range. Local probes found `iphoen` correctly suggested `iPhone`; our generic capitalization gate rejected the mixed-case output. A small canonical product-name list now permits uniquely matching one-edit repairs after native misspelling detection, independently controlled by the existing product-name switch. Correct dictionary words and deliberate mixed/all-capital input remain unchanged.

Native probes also corrected `screensht`, `screnshot`, `screeshot`, and `screesnhot` to `screenshot`; the correct word `screenshot` is preserved. Three- and four-letter words can now accept a uniquely closest first-ranked single-insertion guess when no different system recommendation contradicts it. Equal-distance alternatives still block this fallback. Existing consonant/vowel and native recommendation rules remain in place.

`har` is accepted by the tested native English dictionary and has many different guesses. No static `har → that` rule was added: changing valid words from sentence meaning needs broader disambiguation, not just edit distance. This release does not add a cloud service or language model, nor claim semantic accuracy equal to Grammarly.

Context checks now use each queued completed prefix rather than only the latest full snapshot. Successful edits retain their boundary until a fresh snapshot can evaluate both ordinary spelling and context. Failed verification still clears the queue and never repeats the deletion.
