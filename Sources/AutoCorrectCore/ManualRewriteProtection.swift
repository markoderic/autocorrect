import Foundation

/// Bounded protection for one manually rewritten correction occurrence. It stores no
/// keystrokes: only the replacement, its absolute offset, and up to 32 preceding UTF-16 units
/// from the already-authorized text snapshot. The caller supplies a stable focused-field ID.
public struct ManualRewriteProtection {
    private struct Entry {
        let id: UUID
        let field: UUID
        let location: Int
        let prefixLocation: Int
        let prefix: [UInt16]
        let replacement: String
        let created: TimeInterval
        var manualEdit = false
        var confirmedOverride = false
    }
    private var entries: [Entry] = []
    public init() {}
    public mutating func reset() { entries.removeAll(keepingCapacity: true) }

    /// Invoke only inside successful edit revalidation, immediately before events are posted.
    /// Failed/canceled requests must never be registered. This timing covers physical edits
    /// arriving before the asynchronous post-completion or Accessibility verification.
    @discardableResult
    public mutating func recordPostedCorrection(field: UUID, text: String, windowStart: Int,
                                               range: NSRange, replacement: String, now: TimeInterval) -> UUID? {
        prune(now: now)
        guard (1...256).contains(text.utf16.count), windowStart >= 0,
              windowStart <= Int.max - text.utf16.count,
              range.location >= 0, range.length > 0, range.length <= 120,
              range.location <= text.utf16.count, range.length <= text.utf16.count - range.location,
              UserDictionary.isValidReplacement(replacement), let span = Range(range, in: text),
              isBoundary(span.lowerBound, in: text), isBoundary(span.upperBound, in: text),
              windowStart == 0 || span.lowerBound > text.startIndex else { return nil }
        var start = span.lowerBound
        var length = 0
        while start > text.startIndex {
            let previous = text.index(before: start)
            let units = text[previous..<start].utf16.count
            guard units <= 32 - length else { break }
            start = previous
            length += units
        }
        guard span.lowerBound == text.startIndex || length > 0 else { return nil }
        let location = windowStart + range.location
        entries.removeAll { $0.field == field && $0.location == location }
        let id = UUID()
        entries.append(Entry(id: id, field: field, location: location,
                             prefixLocation: location - length, prefix: Array(text[start..<span.lowerBound].utf16),
                             replacement: replacement, created: now))
        if entries.count > 8 { entries.removeFirst(entries.count - 8) }
        return id
    }

    /// A deletion, native undo, or mouse-based editing action marks existing occurrences.
    /// A fresh snapshot must still prove the same position/context and a changed spelling.
    public mutating func noteManualEdit(now: TimeInterval) {
        prune(now: now)
        for index in entries.indices { entries[index].manualEdit = true }
    }

    public mutating func remove(_ id: UUID) { entries.removeAll { $0.id == id } }

    public mutating func suppresses(field: UUID, candidate: CorrectionCandidate, text: String,
                                   windowStart: Int, now: TimeInterval) -> Bool {
        prune(now: now)
        let length = text.utf16.count
        guard (1...256).contains(length), windowStart >= 0, windowStart <= Int.max - length,
              candidate.range.location >= 0, candidate.range.location <= length,
              candidate.range.length > 0, candidate.range.length <= length - candidate.range.location,
              let span = Range(candidate.range, in: text),
              isBoundary(span.lowerBound, in: text), isBoundary(span.upperBound, in: text),
              String(text[span]) == candidate.original else { return false }
        let location = windowStart + candidate.range.location
        let units = Array(text.utf16)
        for index in entries.indices {
            let entry = entries[index]
            guard entry.manualEdit, entry.field == field, entry.location == location,
                  candidate.original != entry.replacement, windowStart <= entry.prefixLocation else { continue }
            let start = entry.prefixLocation - windowStart
            guard start <= length, entry.prefix.count <= length - start,
                  units[start..<(start + entry.prefix.count)].elementsEqual(entry.prefix) else { continue }
            entries[index].confirmedOverride = true
            return true
        }
        return false
    }

    private mutating func prune(now: TimeInterval) {
        // Once the user's rewrite is confirmed, keep that occurrence until focus/settings
        // reset or bounded-history eviction. Unconfirmed edits expire after two minutes.
        entries.removeAll { !$0.confirmedOverride && (now < $0.created || now - $0.created > 120) }
    }
    private func isBoundary(_ index: String.Index, in text: String) -> Bool {
        index == text.endIndex || text.indices.contains(index)
    }
}
