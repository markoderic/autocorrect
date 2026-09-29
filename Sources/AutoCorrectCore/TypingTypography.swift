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
}
