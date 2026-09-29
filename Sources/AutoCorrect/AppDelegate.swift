import AppKit
import ServiceManagement
import AutoCorrectCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let preferences = Preferences()
    private lazy var engine = CorrectionEngine(preferences: preferences)
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var workspaceObserver: NSObjectProtocol?
    private var settings: SettingsController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = AppIcon.applicationImage()
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        menu.delegate = self
        engine.onChange = { [weak self] in self?.updateIcon(); self?.settings?.updateStatus() }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.engine.focusChanged()
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
        if CommandLine.arguments.contains("--settings") { showSettings() }
        // A one-time system prompt only; permissions are always granted by the user in Settings.
        if !UserDefaults.standard.bool(forKey: "didRequestAccessibility") {
            UserDefaults.standard.set(true, forKey: "didRequestAccessibility")
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(title: "AutoCorrect")
        let settingsItem = NSMenuItem(title: "AutoCorrect Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self; appMenu.addItem(settingsItem); appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit AutoCorrect", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; appMenu.addItem(quitItem); appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let workspaceObserver = workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if preferences.enabled && !engine.isRunning { engine.refresh() }
        rebuildMenu()
    }

    private func updateIcon() {
        statusItem?.button?.image = AppIcon.menuImage()
        statusItem?.button?.title = engine.pending == nil ? "" : "•"
        statusItem?.button?.alphaValue = preferences.enabled ? 1 : 0.45
        statusItem?.button?.setAccessibilityLabel("AutoCorrect")
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
        let heading = item("AutoCorrect")
        heading.attributedTitle = NSAttributedString(string: "AutoCorrect", attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)])
        item(engine.status)
        item("Open AutoCorrect…", action: #selector(showSettings))
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
            let undoItem = item("Undo: \(proposal.original) → \(proposal.replacement)", action: #selector(undo))
            undoItem.keyEquivalent = "z"
            undoItem.keyEquivalentModifierMask = [.control, .option, .command]
            item("Undo & Always Ignore “\(proposal.replacement)”", action: #selector(undoAndIgnore))
        }
        if engine.pending == nil, let word = engine.flaggedWord {
            item("No confident correction for “\(word)”")
            item("Always Ignore “\(word)”", action: #selector(ignoreWord))
        }
        menu.addItem(.separator())
        item("Show Spelling Underlines", action: #selector(toggleUnderlines), checked: preferences.showsSpellingIndicators)
        if let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier {
            let paused = preferences.excludedApps.contains(bundleID)
            let entry = item("\(paused ? "Resume" : "Pause") in \(app.localizedName ?? "This App")", action: #selector(toggleApp(_:)))
            entry.representedObject = bundleID
        }
        let exclusions = NSMenu()
        for bundle in preferences.excludedApps.sorted() {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            let entry = item("Resume in \(name)", action: #selector(toggleApp(_:)), in: exclusions)
            entry.representedObject = bundle
        }
        if !exclusions.items.isEmpty { item("Paused Apps").submenu = exclusions }
        let settingsItem = item("Settings…", action: #selector(showSettings))
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(.separator())
        item("Launch at Login", action: #selector(toggleLogin), checked: SMAppService.mainApp.status == .enabled)
        if SMAppService.mainApp.status == .requiresApproval {
            item("Approve Launch at Login…", action: #selector(loginSettings))
        }
        let permissions = NSMenu()
        item(AXIsProcessTrusted() ? "Accessibility: Allowed" : "Allow Accessibility…", action: #selector(accessibilitySettings), in: permissions)
        item(CGPreflightListenEventAccess() ? "Input Monitoring: Allowed" : "Allow Input Monitoring…", action: #selector(inputSettings), in: permissions)
        item("Recheck Permissions", action: #selector(recheck), in: permissions)
        item("Permissions").submenu = permissions
        menu.addItem(.separator())
        item("Help & Source Code", action: #selector(help))
        item("Quit AutoCorrect", action: #selector(quit))
        updateIcon()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc private func showSettings() {
        if settings == nil {
            let controller = SettingsController(preferences: preferences) { [weak self] in self?.engine.refresh() }
            controller.builtInReplacements = BuiltInReplacements.expansions.merging(BuiltInReplacements.casing) { _, product in product }
            controller.preview = { [weak self] in self?.engine.previewText(in: $0) }
            controller.statusProvider = { [weak self] in
                guard let self = self else { return "" }
                return "\(self.engine.status) · \(self.engine.correctionCount) corrections this session"
            }
            settings = controller
        }
        settings?.present()
    }
    @objc private func toggleUnderlines() { preferences.showsSpellingIndicators.toggle(); engine.refresh() }
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
