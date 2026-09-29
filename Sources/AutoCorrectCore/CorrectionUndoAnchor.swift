import Foundation

/// Locates a previously corrected span without searching for its text. The caller
/// must independently verify the same process, focused element, and safe edit state.
public struct CorrectionUndoAnchor: Equatable, Sendable {
    private let targetRange: NSRange
    private let anchorLocation: Int
    private let anchorUTF16: [UInt16]

    /// `range` is local to the bounded snapshot; `windowStart` is its absolute
    /// UTF-16 offset in the editor. Saves the span plus up to 32 preceding UTF-16
    /// units, always at whole Character boundaries. No text after the span is saved.
    public init?(text: String, windowStart: Int, range: NSRange) {
        let length = text.utf16.count
        guard (1...256).contains(length), windowStart >= 0,
              windowStart <= Int.max - length,
              range.location >= 0, range.location <= length,
              (1...120).contains(range.length), range.length <= length - range.location,
              let span = Range(range, in: text),
              Self.isCharacterBoundary(span.lowerBound, in: text),
              Self.isCharacterBoundary(span.upperBound, in: text) else { return nil }

        var start = span.lowerBound
        var precedingLength = 0
        while start > text.startIndex {
            let previous = text.index(before: start)
            let characterLength = text[previous..<start].utf16.count
            guard characterLength <= 32 - precedingLength else { break }
            precedingLength += characterLength
            start = previous
        }
        // An oversized preceding grapheme cannot supply any bounded context.
        guard span.lowerBound == text.startIndex || precedingLength > 0 else { return nil }
        targetRange = NSRange(location: windowStart + range.location, length: range.length)
        anchorLocation = targetRange.location - precedingLength
        anchorUTF16 = Array(text[start..<span.upperBound].utf16)
    }

    /// Returns the target range local to a fresh snapshot, only when its entire
    /// saved prefix and replacement are present at the original absolute offsets.
    /// Continued typing after the span is permitted; moved or changed spans fail.
    public func matchingRange(in text: String, windowStart: Int) -> NSRange? {
        let length = text.utf16.count
        guard (1...256).contains(length), windowStart >= 0,
              windowStart <= Int.max - length, windowStart <= anchorLocation else { return nil }
        let localAnchor = anchorLocation - windowStart
        guard localAnchor <= length, anchorUTF16.count <= length - localAnchor else { return nil }
        let localTarget = NSRange(location: targetRange.location - windowStart, length: targetRange.length)
        guard let span = Range(localTarget, in: text),
              let anchor = Range(NSRange(location: localAnchor, length: 0), in: text),
              Self.isCharacterBoundary(anchor.lowerBound, in: text),
              Self.isCharacterBoundary(span.lowerBound, in: text),
              Self.isCharacterBoundary(span.upperBound, in: text) else { return nil }
        let units = Array(text.utf16)
        guard units[localAnchor..<(localAnchor + anchorUTF16.count)].elementsEqual(anchorUTF16) else { return nil }
        return localTarget
    }

    private static func isCharacterBoundary(_ index: String.Index, in text: String) -> Bool {
        index == text.endIndex || text.indices.contains(index)
    }
}
