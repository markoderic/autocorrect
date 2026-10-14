import XCTest
import Foundation
@testable import AutoCorrect

/// Opt-in authored fixture capture; never reads the user's text or posts input.
final class TypingAccuracyAuditTests: XCTestCase {
    func testCaptureTypingAccuracy() throws {
        guard let output = ProcessInfo.processInfo.environment["TYPING_AUDIT_OUTPUT"] else { throw XCTSkip("Set TYPING_AUDIT_OUTPUT") }
        let suite = "TypingAudit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.language = "en_US"
        preferences.capitalizesAfterPeriod = false
        let engine = CorrectionEngine(preferences: preferences)
        let positives: [(String, String)] = [
            ("for ecaple ", "for example "), ("spelling mistaked ", "spelling mistakes "),
            ("the user wats to type ", "the user wants to type "), ("anyones computer ", "anyone's computer "),
            ("the men bar ", "the menu bar "), ("now its just working ", "now it's just working "),
            ("in theis prompt ", "in this prompt "), ("wit that ", "with that "),
            ("I agree wit that ", "I agree with that "), ("help wit this ", "help with this "),
            ("work wit them ", "work with them "), ("os we can go ", "so we can go "),
            ("someones phone ", "someone's phone "), ("everyones work ", "everyone's work "),
            ("nobodys fault ", "nobody's fault "), ("the drop down men ", "the drop down menu "),
            ("open the men bar ", "open the menu bar "), ("the file men ", "the file menu "),
            ("she wats to leave ", "she wants to leave "), ("he wats a coffee ", "he wants a coffee "),
            ("we made mistaked ", "we made mistakes "), ("several mistaked ", "several mistakes "),
            ("for exaple ", "for example "), ("an exmple ", "an example "),
            ("the exampel ", "the example "), ("a differnt choice ", "a different choice "),
            ("the documnt ", "the document "), ("the keyboarf ", "the keyboard "),
            ("please rememebr ", "please remember "), ("the problwm ", "the problem "),
            ("the computwr ", "the computer "), ("please contnue ", "please continue "),
            ("the applicatoin ", "the application "), ("please downloa ", "please download "),
            ("use the keyboar ", "use the keyboard "), ("please correc ", "please correct "),
            ("the setings ", "the settings "), ("that is importnt ", "that is important "),
            ("lets focus on this ", "let's focus on this "), ("its a problem ", "it's a problem ")
        ]
        let controls = ["wit ", "his wit ", "her sharp wit ", "a wit that delights ", "wit and wisdom ",
            "the men ", "the men work ", "two men ", "men bar the door ", "the men barred entry ",
            "its working parts ", "its good looks ", "its computer ", "its menu bar ", "she lets go ",
            "OS ", "the OS ", "OS updates ", "macOS ", "iOS ", "import os ", "os.path ",
            "the mist ", "mistakes ", "mistaken ", "mistake ", "watt ", "watts ", "the wants of others ",
            "a book ", "coffee ", "committee ", "theirs ", "their prompt ", "these ",
            "theis@example.com ", "example.com ", "/usr/bin/os ", "variable_name ",
            "Dr. Ngozi ", "we organise ", "the colour ", "someone's phone ", "nobody's fault ",
            "anyone can go ", "the person we met ", "with that ", "the menu bar ", "the example ", "wits "]
        var rows = [[String: Any]]()
        for (text, expected) in positives + controls.map({ ($0, $0) }) {
            var native = [[String: Any]]()
            engine.nativeAssessmentObserver = { lang, miss, proposed, guesses in
                native.append(["language": lang, "misspelled": miss, "proposed": proposed ?? "", "guesses": guesses])
            }
            let start = ProcessInfo.processInfo.systemUptime
            let actual = engine.previewText(in: text) ?? text
            rows.append(["text": text, "expected": expected, "actual": actual, "control": text == expected,
                         "pass": actual == expected, "ms": (ProcessInfo.processInfo.systemUptime - start) * 1000, "native": native])
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
        print("TYPING AUDIT: \(rows.filter { $0["pass"] as? Bool == true }.count)/\(rows.count) exact; output \(output)")
    }
}
