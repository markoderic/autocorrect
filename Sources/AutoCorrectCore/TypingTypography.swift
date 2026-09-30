import Foundation

/// Rich editors substitute these single-unit characters for keyboard punctuation.
/// Keep the allowlist narrow: combining marks, emoji, controls and IME input still
/// cancel a pending edit because their deletion semantics vary between editors.
public enum TypingTypography {
    public static func isSpace(_ character: Character) -> Bool {
        character == " " || character == "\u{00A0}" || character == "\u{202F}"
    }

    public static func isSupportedKeystroke(_ text: String) -> Bool {
        guard text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first else { return false }
        return (0x20...0x7E).contains(scalar.value) || "‘’“”«»\u{00A0}\u{202F}".unicodeScalars.contains(scalar)
    }

    public static func sameBoundary(_ observed: Character, _ typed: Character) -> Bool {
        observed == typed || (isSpace(observed) && isSpace(typed)) ||
            (typed == "\"" && (observed == "“" || observed == "”"))
    }

    /// A host may replace the punctuation we insert with its typographic form (smart
    /// quotes, nonbreaking spaces). Compare unit by unit; letters and case must match.
    /// Only the typed-to-smart direction is equivalent, never the reverse.
    public static func equivalent(observed: String, typed: String) -> Bool {
        let left = Array(observed.utf16)
        let right = Array(typed.utf16)
        guard left.count == right.count else { return false }
        for (observedUnit, typedUnit) in zip(left, right) where observedUnit != typedUnit {
            guard let observedScalar = Unicode.Scalar(observedUnit),
                  let typedScalar = Unicode.Scalar(typedUnit),
                  sameUnit(Character(observedScalar), Character(typedScalar)) else { return false }
        }
        return true
    }

    private static func sameUnit(_ observed: Character, _ typed: Character) -> Bool {
        switch typed {
        case " ": return isSpace(observed)
        case "\"": return "“”«»".contains(observed)
        case "'": return "‘’".contains(observed)
        default: return false
        }
    }
}
