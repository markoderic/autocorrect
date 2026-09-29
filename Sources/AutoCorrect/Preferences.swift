import AppKit

final class Preferences {
    private let defaults = UserDefaults.standard
    var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }
    var asksBeforeCorrecting: Bool {
        get { defaults.bool(forKey: "asksBeforeCorrecting") }
        set { defaults.set(newValue, forKey: "asksBeforeCorrecting") }
    }
    var language: String {
        get { defaults.string(forKey: "language") ?? "en_US" }
        set { defaults.set(newValue, forKey: "language") }
    }
    var ignoredWords: Set<String> {
        get { Set(defaults.stringArray(forKey: "ignoredWords") ?? []) }
        set { defaults.set(newValue.sorted(), forKey: "ignoredWords") }
    }
    var excludedApps: Set<String> {
        get { Set(defaults.stringArray(forKey: "excludedApps") ?? Self.defaultExclusions) }
        set { defaults.set(newValue.sorted(), forKey: "excludedApps") }
    }
    static let defaultExclusions = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode", "com.sublimetext.4",
        "com.jetbrains.intellij", "com.jetbrains.pycharm", "com.jetbrains.WebStorm",
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.Passwords", "org.keepassxc.keepassxc"
    ]
}
