import AppKit

/// A native, nonactivating quick panel. Built only on demand; no timer, web view or
/// permanent event monitor. The standard menu remains available for keyboard navigation.
final class MenuBarPanel {
    private var panel: QuickPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var statusLabel: NSTextField?
    private var countLabel: NSTextField?
    var isShown: Bool { panel?.isVisible == true }

    func update(status: String, count: Int) {
        guard isShown else { return }
        statusLabel?.stringValue = status
        countLabel?.stringValue = "\(count) corrections this session"
    }

    func contains(quartz point: CGPoint) -> Bool {
        guard let panel, panel.isVisible, let screen = NSScreen.screens.first else { return false }
        return panel.frame.contains(NSPoint(x: point.x, y: screen.frame.maxY - point.y))
    }

    func show(relativeTo button: NSStatusBarButton, menu: NSMenu, status: String, count: Int, enabled: Bool, keyboardFocus: Bool = false,
              more: @escaping () -> Void) {
        close()
        guard let parent = button.window else { return }
        let window = QuickPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.acceptsKeyboardFocus = keyboardFocus
        window.title = "AutoCorrect quick controls"
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.level = .popUpMenu; window.isFloatingPanel = true; window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        let effect = NSVisualEffectView()
        effect.material = .popover; effect.blendingMode = .behindWindow; effect.state = .active
        effect.wantsLayer = true; effect.layer?.cornerRadius = 18; effect.layer?.masksToBounds = true
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            effect.state = .inactive; effect.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        window.contentView = effect
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; effect.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -16), effect.widthAnchor.constraint(equalToConstant: 332)])

        let heading = NSStackView(); heading.orientation = .horizontal; heading.spacing = 12
        let image = NSImageView(image: NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: nil) ?? NSImage())
        image.contentTintColor = .controlAccentColor
        image.widthAnchor.constraint(equalToConstant: 34).isActive = true; image.heightAnchor.constraint(equalToConstant: 34).isActive = true
        heading.addArrangedSubview(image)
        let titles = NSStackView(); titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 3
        titles.addArrangedSubview(label("AutoCorrect", size: 21, weight: .bold))
        titles.addArrangedSubview(label("A little help with every word.", size: 11, secondary: true))
        heading.addArrangedSubview(titles); stack.addArrangedSubview(heading)

        let statusCard = NSStackView(); statusCard.orientation = .vertical; statusCard.alignment = .leading; statusCard.spacing = 5
        statusCard.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        statusCard.wantsLayer = true; statusCard.layer?.cornerRadius = 10
        statusCard.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.09).cgColor
        let statusText = label(status, size: 13, weight: .semibold); statusLabel = statusText
        let countText = label("\(count) corrections this session", size: 11, secondary: true); countLabel = countText
        statusCard.addArrangedSubview(statusText); statusCard.addArrangedSubview(countText)
        stack.addArrangedSubview(statusCard); statusCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        var buttons: [PanelAction] = []
        func row(_ entry: NSMenuItem, title: String? = nil, symbol: String, detail: String? = nil) {
            let action = PanelAction(title: title ?? entry.title, symbol: symbol, detail: detail) { [weak self] in
                self?.close()
                guard let selector = entry.action else { return }
                NSApp.sendAction(selector, to: entry.target, from: entry)
            }
            buttons.append(action)
            stack.addArrangedSubview(action); action.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        func entry(_ title: String) -> NSMenuItem? { menu.items.first { $0.title == title } }
        if let entry = entry("Enable AutoCorrect") {
            row(entry, title: enabled ? "Pause corrections" : "Resume corrections", symbol: enabled ? "pause.circle" : "play.circle", detail: "Automatic spelling corrections")
        }
        if let entry = entry("Ask Before Correcting") {
            row(entry, title: entry.state == .on ? "Review before applying" : "Correct automatically", symbol: entry.state == .on ? "hand.raised" : "bolt", detail: "Click to change correction mode")
        }
        let recent = menu.items.filter { $0.title.hasPrefix("Apply:") || $0.title.hasPrefix("Undo:") || $0.title == "Apply Suggestion" }
        if !recent.isEmpty {
            stack.addArrangedSubview(label("READY TO REVIEW", size: 10, weight: .semibold, secondary: true))
            for entry in recent.prefix(2) { row(entry, symbol: entry.title.hasPrefix("Undo:") ? "arrow.uturn.backward" : "checkmark.circle") }
        }
        if let entry = menu.items.first(where: { $0.title.hasPrefix("Pause in ") || $0.title.hasPrefix("Resume in ") }) {
            row(entry, symbol: "app.dashed")
        }
        let divider = NSBox(); divider.boxType = .separator; stack.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        if let entry = entry("Settings…") { row(entry, title: "Writing settings", symbol: "slider.horizontal.3", detail: "Grammar, punctuation & your words") }
        let moreButton = PanelAction(title: "More controls…", symbol: "ellipsis.circle") { [weak self] in self?.close(); more() }
        buttons.append(moreButton)
        stack.addArrangedSubview(moreButton); moreButton.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.addArrangedSubview(label("On-device processing  ·  No typing history", size: 10, secondary: true))
        effect.layoutSubtreeIfNeeded()
        let size = effect.fittingSize
        let anchor = parent.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchor
        window.setFrame(NSRect(x: min(max(anchor.maxX - 332, screen.minX + 8), screen.maxX - 340),
            y: max(screen.minY + 8, anchor.minY - size.height - 8), width: 332, height: size.height), display: false)
        for (index, control) in buttons.enumerated() { control.nextKeyView = buttons[(index + 1) % buttons.count] }
        window.initialFirstResponder = buttons.first
        panel = window
        if keyboardFocus { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(buttons.first) } else { window.orderFrontRegardless() }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in self?.close() }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 { self.close(); return nil }
            if event.type != .keyDown, event.window !== self.panel { self.close() }
            return event
        }
    }

    func close() {
        panel?.orderOut(nil); panel = nil; statusLabel = nil; countLabel = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
    }
    deinit { close() }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight); field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.maximumNumberOfLines = 2
        return field
    }
}

private final class QuickPanel: NSPanel {
    var acceptsKeyboardFocus = false
    override var canBecomeKey: Bool { acceptsKeyboardFocus }
    override var canBecomeMain: Bool { false }
}

private final class PanelAction: NSButton {
    private let handler: () -> Void
    init(title: String, symbol: String, detail: String? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        isBordered = false; alignment = .left; imagePosition = .imageLeading
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.size = NSSize(width: 18, height: 18)
        contentTintColor = .labelColor
        let text = NSMutableAttributedString(string: "  " + title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.labelColor])
        if let detail { text.append(NSAttributedString(string: "\n     " + detail, attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.labelColor.withAlphaComponent(0.8)])) }
        attributedTitle = text
        setAccessibilityLabel(title); setAccessibilityHelp(detail)
        target = self; action = #selector(invoke)
        heightAnchor.constraint(equalToConstant: detail == nil ? 30 : 44).isActive = true
        toolTip = title
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func invoke() { handler() }
}
