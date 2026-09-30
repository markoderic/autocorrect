#!/usr/bin/env python3
"""Simulate candidate edit-type preference rules over recorded native signals.

Input: evaluation/observations.json written by AccuracyEvaluationTests (run with
AUTOCORRECT_EVALUATION=1). The rules here are post-filters on the engine's recorded
automatic replacement, so a rule implemented the same way in the engine behaves
identically. Nothing here touches the app; it is an analysis aid for policy design.

Usage: python3 evaluation/simulate-edit-preference.py [evaluation/observations.json]
"""
import json
import sys
from collections import Counter

VOWELS = set("aeiou")


def osa_distance(a, b):
    """Optimal string alignment distance, matching CorrectionPolicy.editDistance."""
    rows = [[0] * (len(b) + 1) for _ in range(len(a) + 1)]
    for i in range(len(a) + 1):
        rows[i][0] = i
    for j in range(len(b) + 1):
        rows[0][j] = j
    for i in range(1, len(a) + 1):
        for j in range(1, len(b) + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            rows[i][j] = min(rows[i - 1][j] + 1, rows[i][j - 1] + 1, rows[i - 1][j - 1] + cost)
            if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
                rows[i][j] = min(rows[i][j], rows[i - 2][j - 2] + 1)
    return rows[len(a)][len(b)]


def is_subsequence(short, long):
    it = iter(long)
    return all(c in it for c in short)


def edit_type(typed, target):
    """Classify a single-edit relationship; None when not exactly one edit."""
    t, g = typed.lower(), target.lower()
    if t == g or osa_distance(t, g) != 1:
        return None
    if len(g) == len(t) + 1 and is_subsequence(t, g):
        return "INS"
    if len(t) == len(g) + 1 and is_subsequence(g, t):
        return "DEL"
    if len(t) == len(g):
        diffs = [i for i in range(len(t)) if t[i] != g[i]]
        if len(diffs) == 2 and diffs[1] == diffs[0] + 1 and t[diffs[0]] == g[diffs[1]] and t[diffs[1]] == g[diffs[0]]:
            return "TRANS"
        if len(diffs) == 1:
            i = diffs[0]
            return "SUBV" if t[i] in VOWELS and g[i] in VOWELS else "SUBC"
    return None


def plain(word):
    return word is not None and word.isalpha() and word == word.lower()


RANK = {"TRANS": 0, "INS": 0, "DEL": 1, "SUBV": 2, "SUBC": 3}

try:
    WORDS = set(w.strip().lower() for w in open("/usr/share/dict/words"))
except OSError:
    WORDS = set()


def has_double(word):
    return any(word[i] == word[i + 1] for i in range(len(word) - 1))


def removes_doubled_letter(typed, shorter):
    """DEL that drops one letter of a doubled pair (carefull → careful)."""
    t = typed.lower()
    for i in range(len(t)):
        if t[:i] + t[i + 1:] == shorter.lower():
            if (i > 0 and t[i - 1] == t[i]) or (i + 1 < len(t) and t[i + 1] == t[i]):
                return True
    return False


def apply_rule(rule, typed, result, guesses):
    """Return the replacement the rule would produce (None = abstain, result = unchanged)."""
    kind = edit_type(typed, result)
    if kind is None:
        return result  # not a single edit: outside this rule
    candidates = {}
    for guess in guesses[:5]:
        if not plain(guess):
            continue
        k = edit_type(typed, guess)
        if k is not None:
            candidates.setdefault(guess, k)
    candidates[result] = kind
    if rule == "A":  # letters-preserved (TRANS/INS) beat everything; DEL beats SUB
        order = RANK
    elif rule == "B":  # only TRANS/INS outrank; DEL and SUB tie
        order = {"TRANS": 0, "INS": 0, "DEL": 1, "SUBV": 1, "SUBC": 1}
    elif rule == "C":  # DEL beats consonant SUB but not vowel SUB
        order = {"TRANS": 0, "INS": 0, "DEL": 1, "SUBV": 1, "SUBC": 2}
    elif rule == "D":
        # B, plus: a native DEL that removes one of a doubled pair keeps precedence
        # (carefull → careful), and an INS/TRANS winner must be a dictionary word.
        order = {"TRANS": 0, "INS": 0, "DEL": 1, "SUBV": 1, "SUBC": 1}
        if kind == "DEL" and removes_doubled_letter(typed, result):
            return result
        candidates = {g: k for g, k in candidates.items() if k in ("DEL", "SUBV", "SUBC") or g == result or (not WORDS or g.lower() in WORDS)}
    elif rule == "E":
        # D, plus: a native vowel substitution (y counts as a vowel) is kept, and an
        # insertion before the first letter never wins (eminate → geminate).
        order = {"TRANS": 0, "INS": 0, "DEL": 1, "SUBV": 0, "SUBC": 1}
        if kind == "DEL" and removes_doubled_letter(typed, result):
            return result
        if kind == "SUBC":
            i = next(i for i in range(len(typed)) if typed[i] != result[i])
            if typed[i] in VOWELS | {"y"} and result[i] in VOWELS | {"y"}:
                return result
        candidates = {g: k for g, k in candidates.items()
                      if k in ("DEL", "SUBV", "SUBC") or g == result
                      or ((not WORDS or g.lower() in WORDS) and not (k == "INS" and g[1:].lower() == typed.lower()))}
    elif rule == "F":
        # D, plus: native's own vowel substitution (y counts as a vowel) is kept, and an
        # insertion before the first letter never wins (eminate → geminate). Vowel
        # substitution guesses do not tie with insertions (unlike E).
        order = {"TRANS": 0, "INS": 0, "DEL": 1, "SUBV": 1, "SUBC": 1}
        if kind == "DEL" and removes_doubled_letter(typed, result):
            return result
        if kind in ("SUBV", "SUBC"):
            i = next(i for i in range(len(typed)) if typed[i] != result[i])
            if typed[i] in VOWELS | {"y"} and result[i] in VOWELS | {"y"}:
                return result
        candidates = {g: k for g, k in candidates.items()
                      if k in ("DEL", "SUBV", "SUBC") or g == result
                      or ((not WORDS or g.lower() in WORDS) and not (k == "INS" and g[1:].lower() == typed.lower()))}
    else:
        raise ValueError(rule)
    best = min(order[k] for k in candidates.values())
    if order[kind] == best:
        return result
    winners = [g for g, k in candidates.items() if order[k] == best]
    return winners[0] if len(winners) == 1 else None


def promote(typed, guesses):
    """Rule P: with no automatic replacement, accept a unique letter-preserving top-5
    guess at one edit when no other guess is within one edit and it is a dictionary word."""
    close = []
    for guess in guesses[:5]:
        if not plain(guess):
            continue
        k = edit_type(typed, guess)
        if k is not None:
            close.append((guess, k))
    if len(close) != 1:
        return None
    guess, k = close[0]
    if k in ("INS", "TRANS") and (not WORDS or guess.lower() in WORDS):
        return guess
    return None


def outcome(entry, result):
    targets = entry["targets"]
    if len(targets) == 1:
        if result is None:
            return "missed"
        return "correct" if result == targets[0] else "false"
    if result is None:
        return "ambiguous-abstained"
    return "ambiguous-listed" if result in targets else "ambiguous-false"


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "evaluation/observations.json"
    observations = json.load(open(path))
    for context in ["", "please check "]:
        rows = [o for o in observations if o["context"] == context]
        print(f"\n=== context: {'isolated' if not context else context.strip()} ===")
        rules = sys.argv[2].split(",") if len(sys.argv) > 2 else ["A", "B", "C", "D", "P"]
        for rule in rules:
            for held_out in [False, True]:
                transitions = Counter()
                examples = {}
                for o in rows:
                    if o["heldOut"] != held_out:
                        continue
                    typed, result = o["typed"], o["result"]
                    before = outcome(o, result)
                    if rule == "P":
                        if result is not None or not plain(typed) or not o["queried"] or not o["misspelled"]:
                            transitions[(before, before)] += 1
                            continue
                        new = promote(typed, o["guesses"])
                    else:
                        if result is None or not plain(typed) or not plain(result) or not o["queried"]:
                            transitions[(before, before)] += 1
                            continue
                        new = apply_rule(rule, typed, result, o["guesses"])
                    after = outcome(o, new)
                    transitions[(before, after)] += 1
                    if before != after:
                        examples.setdefault((before, after), []).append(f"{typed}→{result}→{new} (expected {o['targets']})")
                changed = {k: v for k, v in transitions.items() if k[0] != k[1]}
                label = "held-out" if held_out else "development"
                print(f"\n-- rule {rule}, {label}: changes {sum(changed.values())}")
                limit = 200 if rule in ("D", "P") else 6
                for (before, after), count in sorted(changed.items(), key=lambda kv: -kv[1]):
                    print(f"   {before} -> {after}: {count}")
                    for example in examples[(before, after)][:limit]:
                        print(f"      {example}")
                totals_before = Counter(k[0] for k in transitions.elements())
                totals_after = Counter(k[1] for k in transitions.elements())
                print(f"   before: correct={totals_before['correct']} false={totals_before['false']} missed={totals_before['missed']}")
                print(f"   after:  correct={totals_after['correct']} false={totals_after['false']} missed={totals_after['missed']}")


if __name__ == "__main__":
    main()
