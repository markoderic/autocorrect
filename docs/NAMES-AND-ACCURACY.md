# Names and spelling accuracy research

Researched and implemented September 29, 2026 for 0.3.3. All native probes used fixed synthetic examples, never text from another app. This is an engineering investigation and regression corpus, not a held-out measurement of everyday accuracy.

## Findings that changed the implementation

**A spelling dictionary is not a capitalization dictionary.** On this Mac, the native checker accepts `powerpoint` and `photoshop` as correctly spelled. It recognizes `Microsoft` as a guess for `microsoft`, but does not necessarily offer an automatic replacement. For `figma`, its automatic answer was `sigma`. An app that only corrects native misspellings cannot consistently recase brands or protect unfamiliar technical names. Microsoft's own [PowerPoint page](https://www.microsoft.com/en-us/microsoft-365/powerpoint) confirms the canonical spelling.

**Damaged contractions need more than apostrophe insertion.** Native probes gave `doesn't` for `doenst`, `dosen't`, and `doens't`. The existing generic edit gate rejected some of these because a letter swap and an apostrophe count as two edits. For `dosent`, the automatic recommendation was `docent`, while the first guess was `doesn't`. The new contraction pass compares apostrophe-free forms against the existing English contraction rules, requires a unique one-edit candidate with a matching initial pair, and uses native support. Without native support, only a unique adjacent transposition retaining all letters can qualify. Correct dictionary words such as `docent`, `does`, `would`, and `wants` never enter that repair pass. Ambiguous `havnt` remains outside automatic contraction repair.

**A big unfiltered name list would introduce wrong corrections.** Company dictionaries include ordinary words, company suffixes, old brands, stock symbols, and multiple capitalization variants. `apple`, `word`, `excel`, `slack`, `zoom`, and similar ordinary words should not be globally recased. Recognizing a known term is deliberately less aggressive than changing it. Short acronyms, conflicting variants, structured tokens, and existing mixed/all-capital input have separate protections.

**Token timing matters for filenames.** Previously a period was itself a completed-word trigger. Typing `doenst.txt` could therefore correct `doenst` before the user had typed `txt`. Colons have the same problem for URL schemes. The boundary queue now waits beyond periods/colons. Once the full structured token is available, existing whole-token validation rejects its modification. This does not promise to identify every filename, especially names with ordinary words separated by spaces; the app does not scan users' files.

## Sources considered

| Source | Useful capability | Decision |
| --- | --- | --- |
| Apple's [NSSpellChecker](https://developer.apple.com/documentation/appkit/nsspellchecker) | Installed spelling dictionary, contextual recommendation, ranked guesses, existing macOS integration | Retain as the general English backend. Native recommendation, rankings, and word acceptance can differ by OS. |
| [CSpell company dictionary](https://github.com/streetsidesoftware/cspell-dicts/tree/152f3ba420772105156cd0ead94a47f9ed493a8d/dictionaries/companies) | Broad company vocabulary and case variants | Bundle filtered recognition words and unambiguous canonical entries. Do not treat a company-list match as semantic proof. |
| [CSpell software dictionaries](https://github.com/streetsidesoftware/cspell-dicts/tree/152f3ba420772105156cd0ead94a47f9ed493a8d/dictionaries/software-terms/src) | Software, services, coding terms, technical acronyms | Use selected sources. Its own README warns that the broad software-terms list contains historically misplaced entries; general terms are recognition-only, not automatically recased. |
| [CSpell file types](https://github.com/streetsidesoftware/cspell-dicts/tree/152f3ba420772105156cd0ead94a47f9ed493a8d/dictionaries/filetypes) | File extension vocabulary | Recognize plain format terms, with a small canonical acronym list. Preserve actual structured filename tokens. |
| [CSpell common misspellings](https://github.com/streetsidesoftware/cspell-dicts/tree/152f3ba420772105156cd0ead94a47f9ed493a8d/dictionaries/en-common-misspellings) | Large explicit typo tables | Not bundled. It uses a different license and a raw typo mapping is not sufficient evidence for silent replacement in arbitrary prose. |
| [Norvig's spelling correction analysis](https://www.norvig.com/spell-correct.html) | Explains why edit distance alone cannot choose intent | Use distance as a gate, not an accuracy/confidence percentage. Preserve native ranking and competing-candidate checks. |
| [SymSpell](https://github.com/wolfgarbe/SymSpell) | Symmetric deletion indexing for candidate retrieval | Independently implement a small one-edit name index in Swift. No SymSpell runtime or code is bundled; its published benchmark numbers do not describe this app. |

## Bundled data and maintenance

The pinned upstream revision is `152f3ba420772105156cd0ead94a47f9ed493a8d`. The bundle contains **6,231 recognition terms** and **2,234 canonical name entries**, plus the app's smaller hand-reviewed product/format rules. Company-name components can contribute individual words; these counts are not the number of distinct companies, nor the number of names guaranteed to be corrected automatically.

[The manifest](lexicon-sources.json) records each input path, size, and SHA-256. `scripts/update-lexicon.py` deterministically regenerates the ASCII word data, excludes ambiguous names from casing, and makes conflicting variants recognition-only. Maintainer regeneration downloads public upstream data; the installed app never performs that download. The filtered Swift source is about 70 KB, before compilation and archive compression.

The three included dictionary packages use the MIT license. [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) retains their notice and describes the transformation. The build copies that notice into the distributed app's Resources directory. No company-word data is silently learned from users' files, contacts, browsing, or typing history.

## Replacement rules

1. Ignored words and explicit user replacements retain precedence.
2. The small canonical product/format rules handle known spellings such as `PowerPoint`, `iPhone`, and `PDF`.
3. For broader exact name matches, automatic casing requires native misspelling detection or a distinctive mixed-case spelling. Known ordinary-word exceptions are excluded. Other recognized technical terms are preserved even with product capitalization switched off.
4. Name typos use a lazy single-deletion index, then exact edit-distance validation. Names must be at least five letters; a unique one-edit match can qualify only when no native suggestion or recommendation is equally close. Two edits need a long name and native top-guess/recommendation agreement. This is bounded dictionary lookup, not a full vocabulary scan on every keystroke.
5. General long-word repair can now accept three edits only for source and target lengths of at least 12, matching first and last letters, agreement between the native automatic answer and first guess, and no equally close competitor among the other checked guesses. Shorter and ambiguous cases retain the earlier limits.
6. A completed boundary still allows at most one spelling and one context edit. Focus/text revalidation, following-text preservation, undo anchors, and manual rewrite protections are unchanged.

## Evidence and remaining limits

New tests exercise the real native checker for contractions, company/software capitalization, missing letters, transpositions, technical recognition, valid common words, and complete filename/URL typing. Existing tests retain context/undo/manual-rewrite coverage. Pure-policy tests exercise ambiguity and language/case gates with deterministic suggestions.

These improvements do not infer arbitrary intended names, identify every company, or supply sentence-level semantic understanding. `har` can still be a valid dictionary word with several possible intended replacements. A company name sharing an ordinary English spelling can remain lowercase. Severe errors without reliable candidate agreement require review. End-to-end keyboard behavior in an individual app is distinct from dictionary/engine tests; no new universal compatibility claim is made.


The optimized local name-index microbenchmark took 12.480 ms to initialize and 0.0041 ms per warmed lookup over 3,000 synthetic fixtures. These are measurements of this lookup helper only; native spelling, cross-app event delivery, memory under long sessions, and battery use are not included. See [validation](VALIDATION.md) for the release test count and exact archive checks.
