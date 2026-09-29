import AppKit
import ServiceManagement
import UniformTypeIdentifiers
import AutoCorrectCore

private final class FlippedDocumentView: NSView { override var isFlipped: Bool { true } }

final class SettingsController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let preferences: Preferences
    private let onSave: () -> Void
    var preview: ((String) -> String?)?
    var statusProvider: (() -> String)?
    var builtInReplacements: [String: String] = [:]
    private let sections = ["Overview", "Writing", "Text Replacements", "Ignored Words", "Apps"]
    private let symbols = ["house", "textformat", "arrow.left.arrow.right", "character.book.closed", "app.badge.checkmark"]
    private let sidebar = NSTableView()
    private let ruleTable = NSTableView()
    private let wordTable = NSTableView()
    private let appTable = NSTableView()
    private let detail = NSView()
    private var section = 0
    private var rules: [(String, String)] = []
    private var words: [String] = []
    private var apps: [(String, String)] = []
    private let fromField = NSTextField()
    private let toField = NSTextField()
    private let wordField = NSTextField()
    private let previewField = NSTextField()
    private let previewResult = NSTextField(wrappingLabelWithString: "Type a word or short sentence ending in a space.")
    private let liveStatus = NSTextField(wrappingLabelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private var filterBuiltins = false

    init(preferences: Preferences, onSave: @escaping () -> Void) {
        self.preferences = preferences
        self.onSave = onSave
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 620), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "AutoCorrect"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 800, height: 570)
        super.init(window: window)
        window.setFrameAutosaveName("AutoCorrectSettings")
        window.center()
        buildShell()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        reloadData()
        renderSection()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func updateStatus() {
        liveStatus.stringValue = statusProvider?() ?? "Ready when you are"
    }

    private func changed() { onSave(); updateStatus() }

    private func reloadData() {
        words = preferences.ignoredWords.sorted()
        var displayed = filterBuiltins ? builtInReplacements : preferences.customCorrections
        if filterBuiltins { displayed.merge(preferences.customCorrections) { _, custom in custom } }
        rules = displayed.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        var known = Dictionary(NSWorkspace.shared.runningApplications.compactMap { app -> (String, String)? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return nil }
            return (id, app.localizedName ?? id)
        }, uniquingKeysWith: { first, _ in first })
        for id in preferences.excludedApps {
            known[id] = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id
        }
        apps = known.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }.map { ($0.key, $0.value) }
        [wordTable, ruleTable, appTable].forEach { $0.reloadData() }
    }

    private func buildShell() {
        guard let root = window?.contentView else { return }
        let material = NSVisualEffectView()
        material.material = .sidebar; material.blendingMode = .behindWindow; material.state = .followsWindowActiveState
        let logo = NSImageView(image: AppIcon.applicationImage(size: 56))
        logo.widthAnchor.constraint(equalToConstant: 44).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let brand = stack([logo, label("AutoCorrect", size: 17, weight: .semibold)], horizontal: true)
        sidebar.headerView = nil; sidebar.rowHeight = 36; sidebar.style = .sourceList
        sidebar.addTableColumn(NSTableColumn(identifier: .init("section")))
        sidebar.dataSource = self; sidebar.delegate = self
        sidebar.focusRingType = .none
        let sidebarScroll = NSScrollView(); sidebarScroll.documentView = sidebar; sidebarScroll.drawsBackground = false
        sidebarScroll.hasVerticalScroller = false
        let aside = stack([brand, sidebarScroll, label("Made for your Mac.\nEverything stays on this device.", size: 11, secondary: true)])
        aside.spacing = 22
        material.addSubview(aside); pin(aside, to: material, inset: 16)
        let line = NSBox(); line.boxType = .separator
        [material, line, detail].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        NSLayoutConstraint.activate([
            material.leadingAnchor.constraint(equalTo: root.leadingAnchor), material.topAnchor.constraint(equalTo: root.topAnchor), material.bottomAnchor.constraint(equalTo: root.bottomAnchor), material.widthAnchor.constraint(equalToConstant: 224),
            line.leadingAnchor.constraint(equalTo: material.trailingAnchor), line.widthAnchor.constraint(equalToConstant: 1), line.topAnchor.constraint(equalTo: root.topAnchor), line.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            detail.leadingAnchor.constraint(equalTo: line.trailingAnchor), detail.trailingAnchor.constraint(equalTo: root.trailingAnchor), detail.topAnchor.constraint(equalTo: root.topAnchor), detail.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebarScroll.widthAnchor.constraint(equalTo: aside.widthAnchor), sidebarScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240)
        ])
        sidebar.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    private func renderSection() {
        detail.subviews.forEach { $0.removeFromSuperview() }
        message.stringValue = ""
        let descriptions = ["A little help with every word.", "Make correction feel right for you.", "Your shortcuts. Your spelling.", "Keep names and personal vocabulary as you type them.", "Choose where AutoCorrect lends a hand."]
        let body = stack([label(sections[section], size: 27, weight: .bold), label(descriptions[section], size: 13, secondary: true)])
        body.spacing = 10
        let gap = NSView(); gap.heightAnchor.constraint(equalToConstant: 6).isActive = true; body.addArrangedSubview(gap)
        switch section {
        case 0: overview(body)
        case 1: writing(body)
        case 2: replacements(body)
        case 3: ignoredWords(body)
        default: applications(body)
        }
        message.font = .systemFont(ofSize: 12); message.textColor = .secondaryLabelColor
        body.addArrangedSubview(message)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let document = FlippedDocumentView(); scroll.documentView = document; document.addSubview(body)
        detail.addSubview(scroll); pin(scroll, to: detail, inset: 0)
        body.translatesAutoresizingMaskIntoConstraints = false; document.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            body.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28), body.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            body.topAnchor.constraint(equalTo: document.topAnchor, constant: 26), body.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28)
        ])
        for view in body.arrangedSubviews { view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
        updateStatus()
    }

    private func overview(_ body: NSStackView) {
        let enabled = toggle("AutoCorrect is enabled", value: preferences.enabled, action: #selector(setEnabled(_:)))
        liveStatus.font = .systemFont(ofSize: 12); liveStatus.textColor = .secondaryLabelColor
        body.addArrangedSubview(card([enabled, liveStatus]))
        let ax = permissionRow("Accessibility", allowed: AXIsProcessTrusted(), action: #selector(accessibility))
        let input = permissionRow("Input Monitoring", allowed: CGPreflightListenEventAccess(), action: #selector(inputMonitoring))
        body.addArrangedSubview(card([label("Permissions", weight: .semibold), ax, input]))
        let login = toggle("Launch at login", value: SMAppService.mainApp.status == .enabled, action: #selector(toggleLogin(_:)))
        var startup: [NSView] = [login]
        if SMAppService.mainApp.status == .requiresApproval { startup.append(button("Approve in System Settings…", #selector(loginSettings))) }
        body.addArrangedSubview(card(startup))
        previewField.placeholderString = "Try: teh quick brown fox "
        previewField.delegate = self; previewField.font = .systemFont(ofSize: 15)
        previewField.setAccessibilityLabel("Try a correction")
        previewResult.font = .systemFont(ofSize: 13); previewResult.textColor = .secondaryLabelColor
        body.addArrangedSubview(card([label("Try it here", weight: .semibold), label("Preview a correction locally, without changing another app.", size: 12, secondary: true), previewField, previewResult]))
        updatePreview()
        body.addArrangedSubview(label("Undo a correction with ⌃⌥⌘Z or from the menu bar.\nSpelling language: \(Locale.current.localizedString(forIdentifier: preferences.language) ?? preferences.language)", size: 12, secondary: true))
    }

    private func writing(_ body: NSStackView) {
        let language = NSPopUpButton(); language.target = self; language.action = #selector(setLanguage(_:))
        for id in (["en_US"] + NSSpellChecker.shared.availableLanguages.filter { $0 != "en_US" }.sorted()) {
            language.addItem(withTitle: Locale.current.localizedString(forIdentifier: id) ?? id)
            language.lastItem?.representedObject = id
            if id == preferences.language { language.select(language.lastItem) }
        }
        body.addArrangedSubview(card([label("Spelling language", weight: .semibold), language]))
        body.addArrangedSubview(card([
            toggle("Ask before correcting", value: preferences.asksBeforeCorrecting, action: #selector(setApproval(_:))),
            label("Review suggestions from the menu bar before they change your text.", size: 12, secondary: true),
            toggle("Check surrounding context", value: preferences.checksContext, action: #selector(setContext(_:))),
            label("Fix clear its/it’s and lets/let’s contexts after nearby words are complete. Uncertain changes need approval.", size: 12, secondary: true)
        ]))
        body.addArrangedSubview(card([
            toggle("Capitalize after a period", value: preferences.capitalizesAfterPeriod, action: #selector(setCapitals(_:))),
            toggle("Show spelling underlines", value: preferences.showsSpellingIndicators, action: #selector(setUnderlines(_:))),
            label("Underlines appear only where the app exposes the word’s position.", size: 12, secondary: true)
        ]))
        body.addArrangedSubview(label("Changes save automatically. AutoCorrect leaves passwords and unsupported text fields alone.", size: 12, secondary: true))
    }

    private func replacements(_ body: NSStackView) {
        body.addArrangedSubview(card([
            toggle("Expand common abbreviations", value: preferences.expandsAbbreviations, action: #selector(setAbbreviations(_:))),
            toggle("Capitalize product names and acronyms", value: preferences.normalizesProductNames, action: #selector(setProducts(_:)))
        ]))
        let filter = NSSegmentedControl(labels: ["My replacements", "Built-in + mine"], trackingMode: .selectOne, target: self, action: #selector(filterRules(_:)))
        filter.selectedSegment = filterBuiltins ? 1 : 0
        body.addArrangedSubview(filter)
        body.addArrangedSubview(table(ruleTable, titles: ["When I type", "Replace with"], height: 190))
        fromField.placeholderString = "e.g. brb"; toField.placeholderString = "e.g. be right back"
        fromField.setAccessibilityLabel("Replacement shortcut"); toField.setAccessibilityLabel("Replacement text")
        let inputs = stack([fromField, toField], horizontal: true); inputs.distribution = .fillEqually
        body.addArrangedSubview(inputs)
        body.addArrangedSubview(stack([button("Add or Update", #selector(addRule)), button("Remove Custom", #selector(removeRule))], horizontal: true))
        body.addArrangedSubview(label("Select a row to edit it. Your replacements override built-ins. To stop a built-in shortcut, add it to Ignored Words.", size: 12, secondary: true))
    }

    private func ignoredWords(_ body: NSStackView) {
        body.addArrangedSubview(table(wordTable, titles: ["Word or name"], height: 265))
        wordField.placeholderString = "Add a word or name"; wordField.setAccessibilityLabel("Ignored word")
        body.addArrangedSubview(stack([wordField, button("Add", #selector(addWord))], horizontal: true))
        body.addArrangedSubview(button("Remove Selected", #selector(removeWord)))
        body.addArrangedSubview(label("Ignored words are never corrected or underlined. Your list stays on this Mac.", size: 12, secondary: true))
    }

    private func applications(_ body: NSStackView) {
        body.addArrangedSubview(label("Running apps and your paused apps appear below. Coding tools, terminals, and password managers start paused.", size: 12, secondary: true))
        body.addArrangedSubview(table(appTable, titles: ["Application", "AutoCorrect"], height: 290))
        body.addArrangedSubview(stack([button("Pause / Resume Selected", #selector(toggleSelectedApp)), button("Add App…", #selector(addApp)), button("Refresh", #selector(refreshApps))], horizontal: true))
        body.addArrangedSubview(label("An allowed app still needs to expose a compatible text field. Some custom editors cannot be corrected.", size: 12, secondary: true))
    }

    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let view = NSTextField(wrappingLabelWithString: text); view.font = .systemFont(ofSize: size, weight: weight)
        view.textColor = secondary ? .secondaryLabelColor : .labelColor
        return view
    }
    private func stack(_ views: [NSView], horizontal: Bool = false) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = horizontal ? .horizontal : .vertical
        stack.alignment = horizontal ? .centerY : .leading; stack.spacing = 12
        return stack
    }
    private func pin(_ view: NSView, to parent: NSView, inset: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset), view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset), view.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset), view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)])
    }
    private func card(_ views: [NSView]) -> NSBox {
        let box = NSBox(); box.boxType = .custom; box.titlePosition = .noTitle; box.borderWidth = 0.5
        box.borderColor = .separatorColor; box.fillColor = .controlBackgroundColor; box.cornerRadius = 10; box.contentViewMargins = .zero
        let content = NSView(); box.contentView = content
        let group = stack(views); content.addSubview(group); pin(group, to: content, inset: 16)
        for view in views { view.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true }
        return box
    }
    private func button(_ title: String, _ action: Selector) -> NSButton { NSButton(title: title, target: self, action: action) }
    private func toggle(_ title: String, value: Bool, action: Selector) -> NSButton {
        let control = NSButton(checkboxWithTitle: title, target: self, action: action); control.state = value ? .on : .off
        return control
    }
    private func permissionRow(_ name: String, allowed: Bool, action: Selector) -> NSStackView {
        let icon = NSImageView(image: NSImage(systemSymbolName: allowed ? "checkmark.circle.fill" : "exclamationmark.circle", accessibilityDescription: allowed ? "Allowed" : "Permission needed")!)
        icon.contentTintColor = allowed ? .systemGreen : .systemOrange
        let title = label(name); title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return stack([icon, title, button(allowed ? "Open Settings" : "Allow…", action)], horizontal: true)
    }
    private func table(_ table: NSTableView, titles: [String], height: CGFloat) -> NSScrollView {
        if table.tableColumns.isEmpty {
            for (index, title) in titles.enumerated() {
                let column = NSTableColumn(identifier: .init(String(index))); column.title = title; column.width = index == 0 ? 280 : 160
                table.addTableColumn(column)
            }
        }
        table.dataSource = self; table.delegate = self; table.rowHeight = 32; table.style = .inset
        table.usesAlternatingRowBackgroundColors = true; table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        return scroll
    }
    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === sidebar { return sections.count }
        if tableView === wordTable { return words.count }
        if tableView === appTable { return apps.count }
        return rules.count
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === sidebar {
            let image = NSImageView(image: NSImage(systemSymbolName: symbols[row], accessibilityDescription: nil)!)
            image.widthAnchor.constraint(equalToConstant: 18).isActive = true; image.contentTintColor = .controlAccentColor
            return stack([image, label(sections[row], weight: .medium)], horizontal: true)
        }
        let first = tableColumn?.identifier.rawValue == "0"
        if tableView === wordTable { return label(words[row]) }
        if tableView === appTable {
            let result = label(first ? apps[row].1 : preferences.excludedApps.contains(apps[row].0) ? "Paused" : "Allowed")
            if !first { result.textColor = preferences.excludedApps.contains(apps[row].0) ? .secondaryLabelColor : .systemGreen }
            return result
        }
        return label(first ? rules[row].0 : rules[row].1)
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        if table === sidebar, sections.indices.contains(table.selectedRow) { section = table.selectedRow; renderSection() }
        if table === ruleTable, rules.indices.contains(table.selectedRow) { fromField.stringValue = rules[table.selectedRow].0; toField.stringValue = rules[table.selectedRow].1 }
    }
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === previewField else { return }
        updatePreview()
    }
    private func updatePreview() {
        if previewField.stringValue.isEmpty { previewResult.stringValue = "Type a word or short sentence ending in a space."; return }
        let text = previewField.stringValue
        if let replacement = preview?(text.last?.isWhitespace == true ? text : text + " ") {
            previewResult.stringValue = "Preview: \(replacement)"; previewResult.textColor = .labelColor
        } else { previewResult.stringValue = "No change suggested."; previewResult.textColor = .secondaryLabelColor }
    }
    private func report(_ error: Error) { message.stringValue = (error as? UserDictionary.ValidationError)?.reason ?? error.localizedDescription; message.textColor = .systemRed }
    private func saved(_ text: String) { reloadData(); changed(); message.stringValue = text; message.textColor = .secondaryLabelColor }
    @objc private func addWord() {
        do { let parsed = try UserDictionary.parse(ignoredText: wordField.stringValue, correctionsText: ""); preferences.ignoredWords.formUnion(parsed.ignoredWords); wordField.stringValue = ""; saved("Word added.") } catch { report(error) }
    }
    @objc private func removeWord() { guard words.indices.contains(wordTable.selectedRow) else { return }; preferences.ignoredWords.remove(words[wordTable.selectedRow]); saved("Word removed.") }
    @objc private func addRule() {
        do { let parsed = try UserDictionary.parse(ignoredText: "", correctionsText: "\(fromField.stringValue) -> \(toField.stringValue)"); preferences.customCorrections.merge(parsed.corrections) { _, new in new }; fromField.stringValue = ""; toField.stringValue = ""; saved("Replacement saved.") } catch { report(error) }
    }
    @objc private func removeRule() {
        guard rules.indices.contains(ruleTable.selectedRow) else { return }
        let key = rules[ruleTable.selectedRow].0
        guard preferences.customCorrections[key] != nil else { message.stringValue = "To disable a built-in, add its shortcut to Ignored Words."; return }
        preferences.customCorrections.removeValue(forKey: key); fromField.stringValue = ""; toField.stringValue = ""; saved("Custom replacement removed.")
    }
    @objc private func filterRules(_ sender: NSSegmentedControl) { filterBuiltins = sender.selectedSegment == 1; reloadData() }
    @objc private func toggleSelectedApp() {
        guard apps.indices.contains(appTable.selectedRow) else { return }; let id = apps[appTable.selectedRow].0
        if preferences.excludedApps.contains(id) { preferences.excludedApps.remove(id) } else { preferences.excludedApps.insert(id) }; saved("App preference saved.")
    }
    @objc private func addApp() {
        let panel = NSOpenPanel(); panel.title = "Choose an app to pause"; panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.applicationBundle]
        guard let window = window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
            self.preferences.excludedApps.insert(id); self.saved("App paused.")
        }
    }
    @objc private func refreshApps() { reloadData() }
    @objc private func setEnabled(_ sender: NSButton) { preferences.enabled = sender.state == .on; changed() }
    @objc private func setApproval(_ sender: NSButton) { preferences.asksBeforeCorrecting = sender.state == .on; changed() }
    @objc private func setContext(_ sender: NSButton) { preferences.checksContext = sender.state == .on; changed() }
    @objc private func setCapitals(_ sender: NSButton) { preferences.capitalizesAfterPeriod = sender.state == .on; changed() }
    @objc private func setUnderlines(_ sender: NSButton) { preferences.showsSpellingIndicators = sender.state == .on; changed() }
    @objc private func setAbbreviations(_ sender: NSButton) { preferences.expandsAbbreviations = sender.state == .on; changed() }
    @objc private func setProducts(_ sender: NSButton) { preferences.normalizesProductNames = sender.state == .on; changed() }
    @objc private func setLanguage(_ sender: NSPopUpButton) { preferences.language = sender.selectedItem?.representedObject as? String ?? "en_US"; changed() }
    @objc private func toggleLogin(_ sender: NSButton) {
        do { if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; renderSection() }
        catch { report(error); sender.state = SMAppService.mainApp.status == .enabled ? .on : .off }
    }
    @objc private func loginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func accessibility() { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary); openPrivacy("Privacy_Accessibility") }
    @objc private func inputMonitoring() { _ = CGRequestListenEventAccess(); openPrivacy("Privacy_ListenEvent") }
    private func openPrivacy(_ anchor: String) { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(url) } }
}
