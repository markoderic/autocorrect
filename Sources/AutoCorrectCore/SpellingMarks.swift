import Foundation

/// One unresolved possible misspelling in the focused field. `location` is an absolute
/// UTF-16 offset in that field; only the flagged word itself is stored, never other text.
public struct SpellingMark: Equatable, Sendable {
    public let location: Int
    public let word: String
    public var range: NSRange { NSRange(location: location, length: word.utf16.count) }

    public init(location: Int, word: String) {
        self.location = location
        self.word = word
    }
}

/// The bounded set of marks for one field, kept sorted by location. Edits shift or drop
/// marks; a fresh text window confirms or removes the marks it covers. Rendering and
/// detection live elsewhere: this is only the shared range model.
public struct SpellingMarkSet: Equatable {
    public static let limit = 32
    public private(set) var marks: [SpellingMark] = []
    public init() {}

    public mutating func removeAll() { marks.removeAll(keepingCapacity: true) }

    /// Adds or replaces the mark at that location. Beyond the limit, the marks farthest
    /// from `caret` are evicted so the region the user is working in stays covered.
    public mutating func insert(_ mark: SpellingMark, near caret: Int) {
        marks.removeAll { $0.location == mark.location }
        marks.append(mark)
        marks.sort { $0.location < $1.location }
        while marks.count > Self.limit,
              let farthest = marks.indices.max(by: { abs(marks[$0].location - caret) < abs(marks[$1].location - caret) }) {
            marks.remove(at: farthest)
        }
    }

    public mutating func remove(at location: Int) { marks.removeAll { $0.location == location } }

    public mutating func remove(word: String) {
        let key = UserDictionary.normalizedKey(word)
        marks.removeAll { UserDictionary.normalizedKey($0.word) == key }
    }

    /// `length` units at `location` became `replacementLength` units. Marks overlapping
    /// the edited span are dropped (their word changed); later marks shift by the delta.
    public mutating func applyEdit(at location: Int, length: Int, replacementLength: Int) {
        let delta = replacementLength - length
        let editEnd = location + length
        marks = marks.compactMap { mark in
            let markEnd = mark.location + mark.word.utf16.count
            let shifted = SpellingMark(location: mark.location + delta, word: mark.word)
            if length == 0 { return mark.location >= location ? shifted : mark }
            if mark.location >= editEnd { return shifted }
            if markEnd <= location { return mark }
            return nil
        }
        marks.sort { $0.location < $1.location }
    }

    /// Confirms marks that fall inside `text` (which starts at `windowStart`): the word
    /// must still be at its location with non-letter neighbors. Marks outside are untouched.
    public mutating func reconcile(text: String, windowStart: Int) {
        let units = Array(text.utf16)
        let windowEnd = windowStart + units.count
        marks.removeAll { mark in
            let start = mark.location - windowStart
            let end = start + mark.word.utf16.count
            guard mark.location >= windowStart, mark.location < windowEnd else { return false }
            // A word cut off by the window edge cannot be judged; leave it for a wider read.
            guard end <= units.count else { return false }
            guard Array(mark.word.utf16) == Array(units[start..<end]) else { return true }
            if start > 0, Self.isLetter(units[start - 1]) { return true }
            if end < units.count, Self.isLetter(units[end]) { return true }
            return false
        }
    }

    /// Replaces every mark inside `range` with the given marks (a fresh scan of that region).
    public mutating func replace(in range: NSRange, with fresh: [SpellingMark], near caret: Int) {
        marks.removeAll { $0.location >= range.location && $0.location < NSMaxRange(range) }
        for mark in fresh { insert(mark, near: caret) }
    }

    /// Drops marks that no longer fit in a field of `length` units (text deleted at the end).
    public mutating func truncate(to length: Int) {
        marks.removeAll { $0.location + $0.word.utf16.count > length }
    }

    private static func isLetter(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return true }
        return CharacterSet.letters.contains(scalar) || scalar == "'" || scalar == "’"
    }
}
