import AppKit
import ApplicationServices

/// A short-lived visual hint. It never changes the target app's text or selection.
final class SpellingIndicator {
    private var panel: UnderlinePanel?
    private var dismissal: DispatchWorkItem?
    private var generation: UInt64 = 0

    func show(snapshot: AccessibilityText.Snapshot, range: NSRange) {
        assert(Thread.isMainThread)
        hide()
        let text = snapshot.text as NSString
        guard range.location >= 0, range.location <= text.length,
              range.length > 0, range.length <= text.length - range.location,
              snapshot.windowStart >= 0,
              AccessibilityText.stillMatches(snapshot) else { return }

        AXUIElementSetMessagingTimeout(snapshot.element, 0.01)
        let absoluteRange = CFRange(location: snapshot.windowStart + range.location, length: range.length)
        // End-character bounds distinguish a single line from a wrapped word's union rect.
        let first = text.rangeOfComposedCharacterSequence(at: range.location)
        let last = text.rangeOfComposedCharacterSequence(at: NSMaxRange(range) - 1)
        guard let wordBounds = bounds(for: absoluteRange, element: snapshot.element),
              let firstBounds = bounds(for: CFRange(location: snapshot.windowStart + first.location, length: first.length), element: snapshot.element),
              let lastBounds = bounds(for: CFRange(location: snapshot.windowStart + last.location, length: last.length), element: snapshot.element),
              valid(wordBounds), valid(firstBounds), valid(lastBounds),
              abs(firstBounds.midY - lastBounds.midY) <= max(firstBounds.height, lastBounds.height) * 0.3,
              wordBounds.height <= max(firstBounds.height, lastBounds.height) * 1.4,
              AccessibilityText.stillMatches(snapshot),
              let frame = overlayFrame(for: wordBounds) else { return }

        let window: UnderlinePanel
        if let panel = panel {
            window = panel
        } else {
            window = UnderlinePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
            panel = window
        }
        window.setFrame(frame, display: false)
        window.contentView?.needsDisplay = true
        window.orderFrontRegardless()

        let ticket = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.generation == ticket else { return }
            self.hide()
        }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    func hide() {
        assert(Thread.isMainThread)
        generation &+= 1
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
    }

    private func bounds(for range: CFRange, element: AXUIElement) -> CGRect? {
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

    private func valid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite &&
            rect.width >= 1 && rect.width <= 1_200 && rect.height >= 4 && rect.height <= 100
    }

    private func overlayFrame(for quartzRect: CGRect) -> NSRect? {
        // AX uses global Quartz points with the main display's top-left as origin.
        // AppKit uses the same main display's bottom-left, including negative
        // coordinates for secondary displays. NSScreen.main may be a different display.
        let screens = NSScreen.screens
        guard let primary = screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        }) else { return nil }
        let word = NSRect(x: quartzRect.minX, y: primary.frame.maxY - quartzRect.maxY,
                          width: quartzRect.width, height: quartzRect.height)
        let frame = NSRect(x: word.minX, y: word.minY - 3, width: word.width, height: 5)
        // Do not draw clipped, off-screen, or display-spanning geometry from a bad AX result.
        guard screens.contains(where: { $0.frame.contains(word) && $0.frame.contains(frame) }) else { return nil }
        return frame
    }

    deinit { dismissal?.cancel() }
}

private final class UnderlinePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class UnderlineView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        let wave = NSBezierPath()
        wave.lineWidth = 1.25
        wave.lineCapStyle = .round
        wave.lineJoinStyle = .round
        let center = bounds.midY
        var x: CGFloat = 0.75
        wave.move(to: NSPoint(x: x, y: center))
        while x < bounds.maxX - 0.75 {
            let next = min(x + 0.5, bounds.maxX - 0.75)
            let y = center + sin((next - 0.75) * .pi / 3) * 1.05
            wave.line(to: NSPoint(x: next, y: y))
            x = next
        }
        NSColor.systemRed.setStroke()
        wave.stroke()
    }
}
