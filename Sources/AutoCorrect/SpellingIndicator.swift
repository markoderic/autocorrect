import AppKit
import ApplicationServices
import AutoCorrectCore

/// Draws red wavy marks beneath unresolved misspellings in one floating, click-through
/// panel. It never changes the target app's text, selection or focus. Geometry comes from
/// Accessibility per mark; marks without trustworthy single-line bounds are not drawn and
/// are reported so the menu can say so instead of pretending.
final class SpellingIndicator {
    struct Placement: Equatable {
        let mark: SpellingMark
        /// Quartz screen coordinates (top-left origin), as AXBoundsForRange reports them.
        let rect: CGRect
    }
    struct Summary: Equatable {
        var placed = 0
        var failed = 0
        var hidden = 0
    }
    typealias BoundsProvider = (CFRange) -> CGRect?
    typealias LineProvider = (Int) -> Int?

    private var panel: UnderlinePanel?

    /// Pure placement: resolves each mark's on-screen rectangle through the providers,
    /// rejects wrapped words and clips to the visible area.
    static func placements(for marks: [SpellingMark], visible: CGRect?, bounds: BoundsProvider,
                           line: LineProvider) -> (placed: [Placement], failed: Int, hidden: Int) {
        var placed: [Placement] = []
        var failed = 0
        var hidden = 0
        for mark in marks.prefix(SpellingMarkSet.limit) {
            let length = mark.word.utf16.count
            guard length > 0 else { failed += 1; continue }
            let wordBounds = bounds(CFRange(location: mark.location, length: length))
            let firstBounds = bounds(CFRange(location: mark.location, length: 1))
            let lastBounds = bounds(CFRange(location: mark.location + length - 1, length: 1))
            var geometry = UnderlineGeometry.singleLine(word: wordBounds, first: firstBounds, last: lastBounds)
            if geometry == nil, firstBounds == nil || lastBounds == nil {
                geometry = UnderlineGeometry.singleLine(word: wordBounds, first: firstBounds, last: lastBounds,
                                                        firstLine: line(mark.location), lastLine: line(mark.location + length - 1))
            }
            guard let geometry else {
                failed += 1
                RuntimeDiagnostics.record("underline: no geometry (word \(Self.describe(wordBounds)), first \(Self.describe(firstBounds)), last \(Self.describe(lastBounds)))")
                continue
            }
            guard let clipped = UnderlineGeometry.clipped(geometry, to: visible) else { hidden += 1; continue }
            placed.append(Placement(mark: mark, rect: clipped))
        }
        return (placed, failed, hidden)
    }

    /// Diagnostic description of a rectangle: sizes and positions only, never text.
    private static func describe(_ rect: CGRect?) -> String {
        guard let rect else { return "missing" }
        return String(format: "%.0fx%.0f@%.0f,%.0f", rect.width, rect.height, rect.minX, rect.minY)
    }

    /// The union of all word rectangles (Quartz coordinates), or nil when nothing is drawn.
    static func panelFrame(for rects: [CGRect]) -> CGRect? {
        guard var union = rects.first else { return nil }
        for rect in rects.dropFirst() { union = union.union(rect) }
        return union
    }

    /// Reads geometry through Accessibility and shows every drawable mark. Returns what
    /// was placed, what lacked geometry and what lies outside the visible editor area.
    @discardableResult
    func render(marks: [SpellingMark], element: AXUIElement) -> Summary {
        assert(Thread.isMainThread)
        guard !marks.isEmpty else { hide(); return Summary() }
        AXUIElementSetMessagingTimeout(element, 0.02)
        let visible = Self.visibleArea(of: element)
        let result = Self.placements(for: marks, visible: visible,
                                     bounds: { Self.bounds(for: $0, element: element) },
                                     line: { Self.line(at: $0, element: element) })
        var summary = Summary(placed: result.placed.count, failed: result.failed, hidden: result.hidden)
        guard let union = Self.panelFrame(for: result.placed.map(\.rect)),
              let frame = Self.overlayFrame(for: union) else {
            RuntimeDiagnostics.record("underline: nothing drawable (\(summary.failed) without geometry, \(summary.hidden) hidden)")
            hide()
            summary.failed += summary.placed
            summary.placed = 0
            return summary
        }
        // Wave rectangles relative to the panel, in AppKit coordinates (bottom-left origin).
        let waves = result.placed.map { placement -> NSRect in
            let local = NSRect(x: placement.rect.minX - union.minX,
                               y: union.maxY - placement.rect.maxY,
                               width: placement.rect.width, height: placement.rect.height)
            return NSRect(x: local.minX, y: local.minY - 3 + Self.inset, width: local.width, height: 5)
        }
        let window = panel ?? Self.makePanel(frame: frame)
        panel = window
        window.setFrame(frame, display: false)
        if let view = window.contentView as? UnderlineView {
            view.waves = waves
            view.needsDisplay = true
        }
        window.orderFrontRegardless()
        RuntimeDiagnostics.record("underline: shown \(summary.placed) mark(s), \(summary.failed) without geometry, \(summary.hidden) hidden")
        if RuntimeDiagnostics.isEnabled, let view = window.contentView as? UnderlineView {
            RuntimeDiagnostics.record("underline: rendered \(view.redPixelCount()) red pixels")
        }
        return summary
    }

    func hide() {
        assert(Thread.isMainThread)
        panel?.orderOut(nil)
    }

    private static let inset: CGFloat = 4

    private static func makePanel(frame: NSRect) -> UnderlinePanel {
        let window = UnderlinePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        let view = UnderlineView(frame: NSRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        view.setAccessibilityElement(false)
        window.contentView = view
        return window
    }

    static func bounds(for range: CFRange, element: AXUIElement) -> CGRect? {
        var range = range
        guard let input = AXValueCreate(.cfRange, &range) else { return nil }
        var output: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, input, &output) == .success,
              let value = output, CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetType(value as! AXValue) == .cgRect else { return nil }
        var result = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &result) else { return nil }
        return result
    }

    static func line(at index: Int, element: AXUIElement) -> Int? {
        var output: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXLineForIndexParameterizedAttribute as CFString,
            NSNumber(value: index), &output) == .success, let number = output as? NSNumber else { return nil }
        return number.intValue
    }

    /// The character range of a line, from AXRangeForLine.
    static func lineRange(for line: Int, element: AXUIElement) -> CFRange? {
        var output: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXRangeForLineParameterizedAttribute as CFString,
            NSNumber(value: line), &output) == .success, let value = output, CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetType(value as! AXValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return range
    }

    /// The editor's visible area: the enclosing scroll area (if any) intersected with its
    /// window, both from AXFrame in Quartz coordinates. Nil when neither can be read.
    static func visibleArea(of element: AXUIElement) -> CGRect? {
        var area: CGRect?
        var current: AXUIElement? = element
        for _ in 0..<12 {
            guard let node = current else { break }
            if let role = AccessibilityText.attribute(node, kAXRoleAttribute) as? String,
               role == kAXScrollAreaRole || role == kAXWindowRole, let frame = frame(of: node) {
                area = area.map { $0.intersection(frame) } ?? frame
                if role == kAXWindowRole { break }
            }
            guard let parent = AccessibilityText.attribute(node, kAXParentAttribute),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            current = (parent as! AXUIElement)
        }
        if area == nil, let window = AccessibilityText.attribute(element, kAXWindowAttribute),
           CFGetTypeID(window) == AXUIElementGetTypeID() {
            area = frame(of: window as! AXUIElement)
        }
        return area
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let value = AccessibilityText.attribute(element, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetType(value as! AXValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    /// Converts the union of word rectangles (Quartz) into an AppKit panel frame with a
    /// small inset for the wave below the baseline. Rejects geometry outside every display.
    static func overlayFrame(for quartzRect: CGRect) -> NSRect? {
        let screens = NSScreen.screens
        guard let primary = screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        }) else { return nil }
        let words = NSRect(x: quartzRect.minX, y: primary.frame.maxY - quartzRect.maxY,
                           width: quartzRect.width, height: quartzRect.height)
        let frame = NSRect(x: words.minX, y: words.minY - inset, width: words.width, height: words.height + inset)
        guard screens.contains(where: { $0.frame.intersects(frame) }) else { return nil }
        return frame
    }
}

private final class UnderlinePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class UnderlineView: NSView {
    var waves: [NSRect] = []
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        NSColor.systemRed.setStroke()
        for rect in waves {
            let wave = NSBezierPath()
            wave.lineWidth = 1.25
            wave.lineCapStyle = .round
            wave.lineJoinStyle = .round
            let center = rect.midY
            var x = rect.minX + 0.75
            wave.move(to: NSPoint(x: x, y: center))
            while x < rect.maxX - 0.75 {
                let next = min(x + 0.5, rect.maxX - 0.75)
                let y = center + sin((next - rect.minX - 0.75) * .pi / 3) * 1.05
                wave.line(to: NSPoint(x: next, y: y))
                x = next
            }
            wave.stroke()
        }
    }

    /// Diagnostic only (tracing): renders this view into a bitmap and counts red pixels,
    /// proving the wave is drawn without needing screen-recording permission.
    func redPixelCount() -> Int {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return -1 }
        cacheDisplay(in: bounds, to: rep)
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                if color.alphaComponent > 0.3, color.redComponent > 0.6, color.greenComponent < 0.5 { count += 1 }
            }
        }
        return count
    }
}
