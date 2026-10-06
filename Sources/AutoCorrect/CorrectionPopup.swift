import AppKit
import ApplicationServices

/// A small native panel for the most recently corrected word. It starts as a quiet dot after
/// the end of the word's line; a deliberate click or the documented shortcut opens the capsule
/// ("original → replacement" with an Undo button), which times out back to the dot. It never activates AutoCorrect, never takes keyboard focus from the editor, never
/// draws without trustworthy single-line Accessibility geometry, and every control is bound to
/// the immutable identity of the one correction it was built for.
final class CorrectionPopup {
    enum Kind: Equatable { case correction, suggestion }
    struct Content: Equatable {
        let id: UUID
        let original: String
        let replacement: String
        var kind: Kind = .correction
        /// A brief explanation shown with a suggestion.
        var detail: String? = nil
    }
    enum Mode: Equatable { case capsule, dot }

    /// Verified geometry in Quartz (top-left origin) coordinates. `word` has already passed
    /// the single-line check; `lineEnd` is the rectangle of the last visible character on the
    /// word's line; `caret` the caret's character rectangle when known; `visible` the editor's
    /// visible area.
    struct Geometry {
        var word: CGRect
        var lineEnd: CGRect?
        var caret: CGRect?
        var visible: CGRect?
    }

    /// Closures bound to one record's id at creation time. Invoking an old set after a newer
    /// correction was shown reports the old id, which the engine refuses.
    struct Actions {
        let id: UUID
        let undo: () -> Void
        let dismiss: () -> Void
        let expand: () -> Void
    }

    var onUndo: ((UUID) -> Void)?
    var onDismiss: ((UUID) -> Void)?
    var onExpand: ((UUID) -> Void)?
    /// The capsule timed out; the owner redraws the dot.
    var onCollapsed: ((UUID) -> Void)?

    private(set) var content: Content?
    private(set) var mode: Mode = .dot
    /// Frame of what is currently displayed (Quartz), nil when hidden.
    private(set) var displayedFrame: CGRect?
    var isShown: Bool { displayedFrame != nil }
    #if DEBUG
    /// Test hook: the actions bound to the view most recently created by `show`.
    private(set) var lastActions: Actions?
    #endif

    private let makesWindows: Bool
    private var panel: PopupPanel?
    private var collapseTimer: Timer?
    private var hovered = false

    static let capsuleHeight: CGFloat = 30
    static let dotSize: CGFloat = 9
    static let gap: CGFloat = 5

    /// `makesWindows: false` computes placement and bindings without creating any window
    /// (tests; never used by the app).
    init(makesWindows: Bool = true) {
        self.makesWindows = makesWindows
    }

    func actions(for content: Content) -> Actions {
        let id = content.id
        return Actions(id: id,
                       undo: { [weak self] in self?.onUndo?(id) },
                       dismiss: { [weak self] in
                           guard let self, self.content?.id == id else { return }
                           self.hide()
                           self.onDismiss?(id)
                       },
                       expand: { [weak self] in self?.onExpand?(id) })
    }

    // MARK: Pure geometry

    /// The word rectangle is trusted only when the first and last character rectangles prove a
    /// single line (same rule as the underlines); any missing or inconsistent piece means no
    /// popup for this correction.
    static func verifiedWord(word: CGRect?, first: CGRect?, last: CGRect?) -> CGRect? {
        guard let rect = UnderlineGeometry.singleLine(word: word, first: first, last: last), isValid(rect) else { return nil }
        return rect
    }

    /// Capsule below the word, else above; clamped to the word's display; never over the caret.
    static func capsuleFrame(word: CGRect, caret: CGRect?, visible: CGRect?, size: CGSize, screens: [CGRect]) -> CGRect? {
        guard isValid(word), size.width > 0, size.height > 0 else { return nil }
        if let visible, !visible.insetBy(dx: -1, dy: -1).contains(CGPoint(x: word.midX, y: word.midY)) { return nil }
        guard let screen = screens.first(where: { $0.contains(CGPoint(x: word.midX, y: word.midY)) }) else { return nil }
        let x = min(max(word.minX, screen.minX + 4), screen.maxX - size.width - 4)
        let below = CGRect(x: x, y: word.maxY + gap, width: size.width, height: size.height)
        let above = CGRect(x: x, y: word.minY - gap - size.height, width: size.width, height: size.height)
        for candidate in [below, above] {
            guard screen.contains(candidate) else { continue }
            if let caret, caret.insetBy(dx: -2, dy: -2).intersects(candidate) { continue }
            return candidate
        }
        return nil
    }

    /// The dot sits after the last character of the word's line, vertically centered on that
    /// line, so it can never cover text on the line; if the caret is there it moves past the
    /// caret. It must lie inside the visible editor area and on a display, or it is not drawn.
    static func dotFrame(lineEnd: CGRect, caret: CGRect?, visible: CGRect?, screens: [CGRect]) -> CGRect? {
        guard isValid(lineEnd) else { return nil }
        var x = lineEnd.maxX + 3
        if let caret, isValid(caret), abs(caret.midY - lineEnd.midY) <= max(caret.height, lineEnd.height) * 0.6 {
            x = max(x, caret.maxX + 3)
        }
        let frame = CGRect(x: x, y: lineEnd.midY - dotSize / 2, width: dotSize, height: dotSize)
        if let caret, caret.insetBy(dx: -1, dy: -1).intersects(frame) { return nil }
        if let visible, !visible.contains(frame) { return nil }
        guard screens.contains(where: { $0.contains(frame) }) else { return nil }
        return frame
    }

    static func isValid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite &&
            rect.width >= 1 && rect.width <= 1_200 && rect.height >= 4 && rect.height <= 100
    }

    static func quartzScreens() -> [CGRect] {
        guard let primary = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        }) else { return [] }
        return NSScreen.screens.map { screen in
            CGRect(x: screen.frame.minX, y: primary.frame.maxY - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        }
    }

    static func appKitFrame(_ quartz: CGRect) -> NSRect? {
        guard let primary = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        }) else { return nil }
        return NSRect(x: quartz.minX, y: primary.frame.maxY - quartz.maxY, width: quartz.width, height: quartz.height)
    }

    /// Whether a system mouse event at `point` (Quartz) lands on the popup. Used by the engine
    /// to leave such clicks to the popup's own controls instead of treating them as editor clicks.
    func contains(quartzPoint point: CGPoint) -> Bool {
        guard let frame = displayedFrame else { return false }
        return frame.insetBy(dx: -2, dy: -2).contains(point)
    }

    // MARK: Showing

    /// Shows the capsule or the dot for `content`. Returns false (and hides) when no trustworthy
    /// placement exists. Placement is decided here; drawing happens only with `makesWindows`.
    @discardableResult
    func show(_ content: Content, mode: Mode, geometry: Geometry, screens: [CGRect]? = nil) -> Bool {
        assert(Thread.isMainThread)
        let screens = screens ?? Self.quartzScreens()
        let bound = actions(for: content)
        #if DEBUG
        lastActions = bound
        #endif
        let frame: CGRect?
        var capsule: CapsuleView?
        var dot: DotView?
        switch mode {
        case .capsule:
            let size: CGSize
            if makesWindows {
                let view = CapsuleView(content: content, actions: bound)
                view.onHover = { [weak self] inside in self?.hovered = inside; if !inside { self?.scheduleCollapse() } }
                size = CGSize(width: view.fittingSize.width, height: Self.capsuleHeight)
                capsule = view
            } else {
                size = CGSize(width: 180, height: Self.capsuleHeight)
            }
            frame = Self.capsuleFrame(word: geometry.word, caret: geometry.caret, visible: geometry.visible, size: size, screens: screens)
        case .dot:
            guard let lineEnd = geometry.lineEnd else { frame = nil; break }
            frame = Self.dotFrame(lineEnd: lineEnd, caret: geometry.caret, visible: geometry.visible, screens: screens)
            if makesWindows { dot = DotView(content: content, actions: bound) }
        }
        guard let frame else {
            hide()
            RuntimeDiagnostics.record("popup: no trustworthy placement for \(mode == .capsule ? "capsule" : "dot")")
            return false
        }
        let changed = self.content != content || self.mode != mode
        self.content = content
        self.mode = mode
        displayedFrame = frame
        if makesWindows, let appKit = Self.appKitFrame(frame) {
            let window = panel ?? PopupPanel.make()
            panel = window
            window.setFrame(appKit, display: false)
            let view: NSView = capsule ?? dot ?? NSView()
            view.frame = NSRect(origin: .zero, size: appKit.size)
            view.autoresizingMask = [.width, .height]
            window.contentView = Self.wrap(view, size: appKit.size, rounded: mode == .capsule ? Self.capsuleHeight / 2 : Self.dotSize / 2)
            if !window.isVisible || changed {
                let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                window.alphaValue = reduceMotion ? 1 : 0
                window.orderFrontRegardless()
                if !reduceMotion {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.12
                        window.animator().alphaValue = 1
                    }
                }
                if mode == .capsule, changed {
                    let announcement = content.kind == .suggestion
                        ? "AutoCorrect suggests changing \(content.original) to \(content.replacement). Apply or dismiss."
                        : "AutoCorrect changed \(content.original) to \(content.replacement). Undo is available."
                    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                         userInfo: [.announcement: announcement,
                                                    .priority: NSAccessibilityPriorityLevel.medium.rawValue])
                }
            } else {
                window.orderFrontRegardless()
            }
        }
        RuntimeDiagnostics.record("popup: shown \(mode == .capsule ? "capsule" : "dot") \(Int(frame.width))x\(Int(frame.height))")
        if mode == .capsule { scheduleCollapse() } else { collapseTimer?.invalidate() }
        return true
    }

    /// Hides without forgetting the record; the owner re-renders after a pause.
    func hide() {
        assert(Thread.isMainThread)
        collapseTimer?.invalidate()
        collapseTimer = nil
        displayedFrame = nil
        panel?.orderOut(nil)
    }

    /// Hides and forgets the record (field change, expiry, undo, invalidation).
    func clear() {
        hide()
        content = nil
        mode = .dot
    }

    private func scheduleCollapse() {
        collapseTimer?.invalidate()
        guard mode == .capsule else { return }
        collapseTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            guard let self, !self.hovered, self.mode == .capsule, let content = self.content else { return }
            self.mode = .dot
            self.hide()
            self.onCollapsed?(content.id)
        }
    }

    /// Glass on macOS 26 and later, looked up by name so the code also compiles with older SDKs
    /// (the hosted macOS 14 toolchain); the popover material before that; an opaque, bordered
    /// surface under Reduce Transparency or Increase Contrast.
    private static func wrap(_ view: NSView, size: CGSize, rounded radius: CGFloat) -> NSView {
        let workspace = NSWorkspace.shared
        let plain = workspace.accessibilityDisplayShouldReduceTransparency || workspace.accessibilityDisplayShouldIncreaseContrast
        if !plain, #available(macOS 26.0, *), let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassClass.init(frame: NSRect(origin: .zero, size: size))
            if glass.responds(to: NSSelectorFromString("setCornerRadius:")) { glass.setValue(radius, forKey: "cornerRadius") }
            if glass.responds(to: NSSelectorFromString("setContentView:")) {
                glass.setValue(view, forKey: "contentView")
            } else {
                glass.addSubview(view)
            }
            glass.autoresizingMask = [.width, .height]
            return glass
        }
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = plain ? .windowBackground : .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = radius
        effect.layer?.masksToBounds = true
        if plain {
            effect.layer?.borderWidth = 1
            effect.layer?.borderColor = NSColor.separatorColor.cgColor
        }
        effect.addSubview(view)
        effect.autoresizingMask = [.width, .height]
        return effect
    }
}

private final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    static func make() -> PopupPanel {
        let window = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.setAccessibilityRole(.group)
        window.setAccessibilityLabel("AutoCorrect correction")
        return window
    }
}

/// "original → replacement   [Undo] [×]" on one line. Its controls call the actions that were
/// bound to this view's record when it was created.
private final class CapsuleView: NSView {
    var onHover: ((Bool) -> Void)?
    private let actions: CorrectionPopup.Actions
    private let stack = NSStackView()

    init(content: CorrectionPopup.Content, actions: CorrectionPopup.Actions) {
        self.actions = actions
        super.init(frame: .zero)
        let text = NSMutableAttributedString(string: content.original, attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue])
        text.append(NSAttributedString(string: "  →  ", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.tertiaryLabelColor]))
        text.append(NSAttributedString(string: content.replacement, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor]))
        if let detail = content.detail, !detail.isEmpty {
            text.append(NSAttributedString(string: "   " + detail, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        let label = NSTextField(labelWithAttributedString: text)
        let isSuggestion = content.kind == .suggestion
        label.setAccessibilityLabel(isSuggestion ? "Suggestion: change \(content.original) to \(content.replacement). \(content.detail ?? "")"
                                                 : "Changed \(content.original) to \(content.replacement)")
        let undo = NSButton(title: isSuggestion ? "Apply" : "Undo", target: self, action: #selector(undoClicked))
        undo.bezelStyle = .accessoryBarAction
        undo.controlSize = .small
        undo.font = .systemFont(ofSize: 11, weight: .medium)
        undo.setAccessibilityLabel(isSuggestion ? "Apply suggestion: \(content.original) to \(content.replacement)"
                                                : "Undo correction of \(content.original) to \(content.replacement)")
        undo.setAccessibilityHelp(isSuggestion ? "Also available from the AutoCorrect menu" : "Also available with Control-Option-Command-Z")
        let close = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Dismiss")!, target: self, action: #selector(dismissClicked))
        close.isBordered = false
        close.contentTintColor = .tertiaryLabelColor
        close.setAccessibilityLabel("Dismiss this indicator")
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(undo)
        stack.addArrangedSubview(close)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(content.kind == .suggestion ? "AutoCorrect suggests changing \(content.original) to \(content.replacement)"
                                                          : "AutoCorrect changed \(content.original) to \(content.replacement)")
    }
    required init?(coder: NSCoder) { nil }

    override var fittingSize: NSSize {
        let size = stack.fittingSize
        return NSSize(width: ceil(size.width), height: CorrectionPopup.capsuleHeight)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func undoClicked() { actions.undo() }
    @objc private func dismissClicked() { actions.dismiss() }
}

/// The quiet indicator: a small accent-colored dot after the end of the corrected word's line.
private final class DotView: NSView {
    private let actions: CorrectionPopup.Actions
    init(content: CorrectionPopup.Content, actions: CorrectionPopup.Actions) {
        self.actions = actions
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(content.kind == .suggestion ? "Suggestion: \(content.original) could be \(content.replacement). Click to review."
                                                          : "Recent correction: \(content.original) changed to \(content.replacement). Click to review or undo.")
        toolTip = "\(content.original) → \(content.replacement). Click to review" + (content.kind == .suggestion ? "" : ", or press Control-Option-Command-/")
    }
    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); dirtyRect.fill(using: .copy)
        NSColor.controlAccentColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { actions.expand() }
    override func accessibilityPerformPress() -> Bool { actions.expand(); return true }
}
