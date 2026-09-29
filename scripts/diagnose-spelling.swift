// Fixed, non-user-text fixtures for diagnosing differences between macOS dictionaries.
import AppKit
let checker = NSSpellChecker.shared
let tag = NSSpellChecker.uniqueSpellDocumentTag()
for word in ["teh", "chek", "recieve", "wierd", "frend", "receving", "capitazed", "speoll"] {
    let isolatedRange = NSRange(location: 0, length: word.utf16.count)
    for prefix in ["", "please check ", "Done. "] {
        let text = prefix + word + " "
        let range = NSRange(location: prefix.utf16.count, length: word.utf16.count)
        let correction = checker.correction(forWordRange: range, in: text, language: "en_US", inSpellDocumentWithTag: tag)
        let guesses = checker.guesses(forWordRange: range, in: text, language: "en_US", inSpellDocumentWithTag: tag) ?? []
        let isolatedTag = NSSpellChecker.uniqueSpellDocumentTag()
        let isolated = checker.correction(forWordRange: isolatedRange, in: word + " ", language: "en_US", inSpellDocumentWithTag: isolatedTag)
        checker.closeSpellDocument(withTag: isolatedTag)
        print("FIXTURE \(text.debugDescription): correction=\(correction ?? "nil") guesses=\(guesses.prefix(6)) isolated=\(isolated ?? "nil")")
    }
}
checker.closeSpellDocument(withTag: tag)
