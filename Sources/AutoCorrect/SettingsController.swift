import AppKit
import AutoCorrectCore

final class SettingsController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let preferences: Preferences
    private let onSave: () -> Void
    private var words: [String] = []
    private var rules: [(String, String)] = []
    private let wordTable = NSTableView()
    private let ruleTable = NSTableView()
    private let wordField = NSTextField()
    private let fromField = NSTextField()
    private let toField = NSTextField()
    private let message = NSTextField(wrappingLabelWithString: "")
    private let underlines = NSButton(checkboxWithTitle: "Show red spelling underlines", target: nil, action: nil)
    private let approval = NSButton(checkboxWithTitle: "Ask before applying corrections", target: nil, action: nil)
    private let language = NSPopUpButton()

    init(preferences: Preferences, onSave: @escaping () -> Void) {
        self.preferences = preferences
        self.onSave = onSave
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 430), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "AutoCorrect Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        words = preferences.ignoredWords.sorted()
        rules = preferences.customCorrections.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        wordTable.reloadData()
        ruleTable.reloadData()
        wordField.stringValue = ""; fromField.stringValue = ""; toField.stringValue = ""
        underlines.state = preferences.showsSpellingIndicators ? .on : .off
        approval.state = preferences.asksBeforeCorrecting ? .on : .off
        language.selectItem(withTitle: "English (US)")
        for item in language.itemArray where item.representedObject as? String == preferences.language { language.select(item) }
        message.stringValue = ""
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
    }
    private func stack(_ views: [NSView], horizontal: Bool = false) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = horizontal ? .horizontal : .vertical
        stack.alignment = horizontal ? .centerY : .leading
        stack.spacing = 12
        return stack
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }
    private func tableView(_ table: NSTableView, titles: [String]) -> NSScrollView {
        table.dataSource = self; table.delegate = self
        table.rowHeight = 27
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        for (index, title) in titles.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
            column.title = title
            column.width = titles.count == 1 ? 450 : 225
            table.addTableColumn(column)
        }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 160).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 482).isActive = true
        return scroll
    }
    private func build() {
        guard let content = window?.contentView else { return }
        let tabs = NSTabView()
        func addTab(_ title: String, content: NSStackView) {
            let tab = NSTabViewItem(identifier: title)
            tab.label = title
            let container = NSView()
            container.addSubview(content)
            content.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16), content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16), content.topAnchor.constraint(equalTo: container.topAnchor, constant: 20)])
            tab.view = container
            tabs.addTabViewItem(tab)
        }
        let languageIDs = ["en_US"] + NSSpellChecker.shared.availableLanguages.filter { $0 != "en_US" }.sorted()
        for id in languageIDs {
            language.addItem(withTitle: id == "en_US" ? "English (US)" : Locale.current.localizedString(forIdentifier: id) ?? id)
            language.lastItem?.representedObject = id
        }
        addTab("General", content: stack([
            stack([NSTextField(labelWithString: "Language"), language], horizontal: true),
            approval, underlines,
            label("Underlines mark possible misspellings in supported text fields. They clear when you type, click, scroll, or switch apps."),
            label("Apple’s local dictionaries check both common and uncommon words. Uncertain suggestions wait for your approval. Custom corrections use the exact spelling you choose.")
        ]))
        wordField.placeholderString = "Word or name, e.g. Marko"
        wordField.widthAnchor.constraint(equalToConstant: 250).isActive = true
        addTab("Ignored Words", content: stack([
            label("These words and names will never be corrected or underlined. Remove a word to check it again."),
            tableView(wordTable, titles: ["Word or name"]),
            stack([wordField, button("Add", #selector(addWord)), button("Remove", #selector(removeWord))], horizontal: true)
        ]))
        fromField.placeholderString = "When I type"
        toField.placeholderString = "Replace with"
        fromField.widthAnchor.constraint(equalToConstant: 145).isActive = true
        toField.widthAnchor.constraint(equalToConstant: 145).isActive = true
        addTab("Custom Corrections", content: stack([
            label("Choose your own spelling, including names. Add an existing typed word again to update its correction."),
            tableView(ruleTable, titles: ["When I type", "Replace with"]),
            stack([fromField, toField, button("Add", #selector(addRule)), button("Remove", #selector(removeRule))], horizontal: true)
        ]))
        message.textColor = .systemRed
        message.font = .systemFont(ofSize: 11)
        let save = button("Save", #selector(save))
        save.keyEquivalent = "\r"
        let cancel = button("Cancel", #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let footer = stack([message, cancel, save], horizontal: true)
        let root = stack([tabs, footer])
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20), root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 16), root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            tabs.widthAnchor.constraint(equalTo: root.widthAnchor), tabs.heightAnchor.constraint(equalToConstant: 330),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor), message.widthAnchor.constraint(greaterThanOrEqualToConstant: 320)
        ])
    }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView === wordTable ? words.count : rules.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text = tableView === wordTable ? words[row] : tableColumn?.identifier.rawValue == "0" ? rules[row].0 : rules[row].1
        return NSTextField(labelWithString: text)
    }
    private func report(_ error: Error) {
        message.stringValue = (error as? UserDictionary.ValidationError)?.reason ?? error.localizedDescription
    }
    @objc private func addWord() {
        do {
            let parsed = try UserDictionary.parse(ignoredText: wordField.stringValue, correctionsText: "")
            words = Set(words).union(parsed.ignoredWords).sorted()
            wordField.stringValue = ""; message.stringValue = ""; wordTable.reloadData()
        } catch { report(error) }
    }
    @objc private func removeWord() {
        guard words.indices.contains(wordTable.selectedRow) else { return }
        words.remove(at: wordTable.selectedRow); wordTable.reloadData()
    }
    @objc private func addRule() {
        do {
            let parsed = try UserDictionary.parse(ignoredText: "", correctionsText: "\(fromField.stringValue) -> \(toField.stringValue)")
            if let rule = parsed.corrections.first {
                rules.removeAll { $0.0 == rule.key }
                rules.append((rule.key, rule.value)); rules.sort { $0.0 < $1.0 }
            }
            fromField.stringValue = ""; toField.stringValue = ""; message.stringValue = ""; ruleTable.reloadData()
        } catch { report(error) }
    }
    @objc private func removeRule() {
        guard rules.indices.contains(ruleTable.selectedRow) else { return }
        rules.remove(at: ruleTable.selectedRow); ruleTable.reloadData()
    }
    @objc private func save() {
        // Don't silently discard a word that has been typed but not added to its list.
        if !wordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { addWord(); if !message.stringValue.isEmpty { return } }
        if !fromField.stringValue.isEmpty || !toField.stringValue.isEmpty { addRule(); if !message.stringValue.isEmpty { return } }
        do {
            let dictionary = try UserDictionary.parse(ignoredText: words.joined(separator: "\n"), correctionsText: rules.map { "\($0.0) -> \($0.1)" }.joined(separator: "\n"))
            preferences.ignoredWords = dictionary.ignoredWords
            preferences.customCorrections = dictionary.corrections
            preferences.showsSpellingIndicators = underlines.state == .on
            preferences.asksBeforeCorrecting = approval.state == .on
            preferences.language = language.selectedItem?.representedObject as? String ?? "en_US"
            onSave(); close()
        } catch { report(error) }
    }
    @objc private func cancel() { close() }
}
