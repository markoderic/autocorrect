import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let preferences = Preferences()
    private lazy var engine = CorrectionEngine(preferences: preferences)
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var workspaceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        menu.delegate = self
        engine.onChange = { [weak self] in self?.updateIcon() }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.engine.invalidate()
            self?.updateIcon()
        }
        // Warm the system spelling service before installing the active event tap.
        _ = engine.suggestion("teh")
        engine.refresh()
        if !UserDefaults.standard.bool(forKey: "didConfigureLogin"), Bundle.main.bundleURL.pathExtension == "app" {
            do {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: "didConfigureLogin")
            } catch { /* Menu exposes actual status and allows retry; app still runs normally. */ }
        }
        rebuildMenu()
        // A one-time system prompt only; permissions are always granted by the user in Settings.
        if !UserDefaults.standard.bool(forKey: "didRequestAccessibility") {
            UserDefaults.standard.set(true, forKey: "didRequestAccessibility")
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let workspaceObserver = workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if preferences.enabled && !engine.isRunning { engine.refresh() }
        rebuildMenu()
    }

    private func updateIcon() {
        let symbol = !preferences.enabled ? "text.badge.minus" : engine.pending != nil ? "text.badge.plus" : "text.badge.checkmark"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "AutoCorrect")
        statusItem?.button?.image?.isTemplate = true
        statusItem?.button?.title = preferences.enabled && !engine.isRunning ? "!" : engine.pending != nil ? "1" : ""
        statusItem?.button?.toolTip = "AutoCorrect — \(engine.status)"
    }

    @discardableResult
    private func item(_ title: String, action: Selector? = nil, checked: Bool? = nil, in targetMenu: NSMenu? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        if let checked = checked { entry.state = checked ? .on : .off }
        (targetMenu ?? menu).addItem(entry)
        return entry
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        item("AutoCorrect")
        item(engine.status)
        menu.addItem(.separator())
        item("Enable AutoCorrect", action: #selector(toggleEnabled), checked: preferences.enabled)
        item("Ask Before Correcting", action: #selector(toggleApproval), checked: preferences.asksBeforeCorrecting)
        if let proposal = engine.pending {
            item("Apply: \(proposal.original) → \(proposal.replacement)", action: #selector(approve))
            item("Always Ignore “\(proposal.original)”", action: #selector(ignoreWord))
        } else if preferences.asksBeforeCorrecting {
            item("Suggestions appear here as you type")
        }
        if let proposal = engine.undoProposal {
            item("Undo: \(proposal.original) → \(proposal.replacement)", action: #selector(undo))
            item("Undo & Always Ignore “\(proposal.replacement)”", action: #selector(undoAndIgnore))
        }
        item("\(engine.correctionCount) correction\(engine.correctionCount == 1 ? "" : "s") this session")
        menu.addItem(.separator())
        if let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier {
            let entry = item("Pause in \(app.localizedName ?? bundleID)", action: #selector(toggleApp(_:)), checked: preferences.excludedApps.contains(bundleID))
            entry.representedObject = bundleID
        }
        let exclusions = NSMenu()
        for bundle in preferences.excludedApps.sorted() {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            let name = url?.deletingPathExtension().lastPathComponent ?? bundle
            let entry = item(name, action: #selector(toggleApp(_:)), checked: true, in: exclusions)
            entry.representedObject = bundle
        }
        item("Paused Apps").submenu = exclusions
        let languages = NSMenu()
        for language in NSSpellChecker.shared.availableLanguages.sorted() {
            let label = Locale.current.localizedString(forIdentifier: language) ?? language
            let entry = item(label, action: #selector(setLanguage(_:)), checked: preferences.language == language, in: languages)
            entry.representedObject = language
        }
        item("Spelling Language").submenu = languages
        if !preferences.ignoredWords.isEmpty {
            let words = NSMenu()
            for word in preferences.ignoredWords.sorted() {
                let entry = item(word, action: #selector(unignoreWord(_:)), checked: true, in: words)
                entry.representedObject = word
            }
            item("Ignored Words").submenu = words
        }
        menu.addItem(.separator())
        item("Launch at Login", action: #selector(toggleLogin), checked: SMAppService.mainApp.status == .enabled)
        if SMAppService.mainApp.status == .requiresApproval {
            item("Approve Launch at Login…", action: #selector(loginSettings))
        }
        item(AXIsProcessTrusted() ? "Accessibility: Allowed" : "Allow Accessibility…", action: #selector(accessibilitySettings))
        item(CGPreflightListenEventAccess() ? "Input Monitoring: Allowed" : "Allow Input Monitoring…", action: #selector(inputSettings))
        item("Recheck Permissions", action: #selector(recheck))
        menu.addItem(.separator())
        item("Help & Source Code", action: #selector(help))
        item("Quit AutoCorrect", action: #selector(quit))
        updateIcon()
    }

    @objc private func toggleEnabled() { preferences.enabled.toggle(); engine.refresh() }
    @objc private func toggleApproval() { preferences.asksBeforeCorrecting.toggle(); engine.refresh() }
    @objc private func approve() { engine.approve() }
    @objc private func undo() { engine.undo() }
    @objc private func undoAndIgnore() { engine.undo(andIgnore: true) }
    @objc private func ignoreWord() { engine.ignorePendingWord() }
    @objc private func toggleApp(_ sender: NSMenuItem) {
        guard let bundle = sender.representedObject as? String else { return }
        if preferences.excludedApps.contains(bundle) { preferences.excludedApps.remove(bundle) }
        else { preferences.excludedApps.insert(bundle) }
        engine.refresh()
    }
    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? String else { return }
        preferences.language = language
        engine.refresh()
    }
    @objc private func unignoreWord(_ sender: NSMenuItem) {
        guard let word = sender.representedObject as? String else { return }
        preferences.ignoredWords.remove(word)
        engine.refresh()
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
    @objc private func loginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func accessibilitySettings() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        openSettings("Privacy_Accessibility")
    }
    @objc private func inputSettings() {
        _ = CGRequestListenEventAccess()
        openSettings("Privacy_ListenEvent")
    }
    private func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(url) }
    }
    @objc private func recheck() { engine.refresh() }
    @objc private func help() { NSWorkspace.shared.open(URL(string: "https://github.com/markoderic/autocorrect#readme")!) }
    @objc private func quit() { NSApp.terminate(nil) }
}
