import Foundation

/// Remembers word boundaries, never the characters the user types. Offsets are
/// relative to the current caret so a correction before a later boundary preserves it.
public struct CompletedWordBacklog {
    public struct Boundary: Equatable {
        public let id: UInt64
        public fileprivate(set) var trailingUTF16: Int
        public let delimiter: Character
        public fileprivate(set) var spellingCorrected = false
        public fileprivate(set) var contextCorrected = false

        public func completedPrefix(in text: String) -> String? {
            let end = text.utf16.count - trailingUTF16
            guard end > 0, let range = Range(NSRange(location: 0, length: end), in: text),
                  text[range].last == delimiter else { return nil }
            return String(text[range])
        }
    }
    public private(set) var boundaries: [Boundary] = []
    private var previousWasDelimiter = true
    private var nextID: UInt64 = 0
    public init() {}

    public mutating func reset() {
        boundaries.removeAll(keepingCapacity: true)
        previousWasDelimiter = true
    }

    /// Navigation, deletion, paste, modifiers, focus, and mouse changes must reset
    /// this queue. Only a single printable ASCII keyboard character is accepted.
    public mutating func append(_ text: String) {
        guard text.utf16.count == 1, let scalar = text.unicodeScalars.first,
              (0x20...0x7E).contains(scalar.value), let character = text.first else { reset(); return }
        for index in boundaries.indices { boundaries[index].trailingUTF16 += 1 }
        boundaries.removeAll { $0.trailingUTF16 > 96 }
        let delimiter = CorrectionPolicy.isDelimiter(character)
        if delimiter && !previousWasDelimiter {
            nextID &+= 1
            boundaries.append(Boundary(id: nextID, trailingUTF16: 0, delimiter: character))
            if boundaries.count > 8 { boundaries.removeFirst(boundaries.count - 8) }
        }
        previousWasDelimiter = delimiter
    }

    /// A successful edit retains the boundary for the other pass only. Never run a
    /// user mapping or context correction twice at the same boundary (A → B → A).
    public mutating func recordCorrection(_ id: UInt64, contextual: Bool) {
        guard let index = boundaries.firstIndex(where: { $0.id == id }) else { return }
        if contextual { boundaries[index].contextCorrected = true }
        else { boundaries[index].spellingCorrected = true }
    }

    public mutating func remove(_ id: UInt64) { boundaries.removeAll { $0.id == id } }
}
