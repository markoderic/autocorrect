import Foundation

/// Accept alternate AX geometry only when it still establishes a single text line.
enum UnderlineGeometry {
    static func singleLine(word: CGRect?, first: CGRect?, last: CGRect?,
                           firstLine: Int? = nil, lastLine: Int? = nil) -> CGRect? {
        if let first, let last, valid(first), valid(last) {
            guard abs(first.midY - last.midY) <= max(first.height, last.height) * 0.3 else { return nil }
            let union = first.union(last)
            let result = word ?? union
            guard valid(result), result.height <= max(first.height, last.height) * 1.4,
                  result.insetBy(dx: -2, dy: -2).contains(union) else { return nil }
            return result
        }
        // Some editors expose whole-word bounds and line indices, but no per-letter
        // rectangles. Equal line indices provide the missing wrap check.
        guard let word, valid(word), let firstLine, firstLine >= 0, firstLine == lastLine else { return nil }
        return word
    }

    private static func valid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite &&
            rect.width >= 1 && rect.width <= 1_200 && rect.height >= 4 && rect.height <= 100
    }
}
