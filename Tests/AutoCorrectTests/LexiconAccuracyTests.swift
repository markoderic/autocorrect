import XCTest
import AutoCorrectCore
@testable import AutoCorrect

final class LexiconAccuracyTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var preferences: Preferences!
    private var engine: CorrectionEngine!
    override func setUp() {
        suite = "AutoCorrectLexiconTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        preferences = Preferences(defaults: defaults)
        preferences.language = "en_US"
        engine = CorrectionEngine(preferences: preferences)
    }
    override func tearDown() {
        engine = nil
        defaults.removePersistentDomain(forName: suite)
    }

    func testReportedContractionErrorsUseNativeDictionaryAndGeneralRepair() {
        for (source, expected) in ["doenst": "doesn't", "dosent": "doesn't", "dosen't": "doesn't",
                                   "doens't": "doesn't", "Doenst": "Doesn't", "doesn": "doesn't",
                                   "woudlnt": "wouldn't", "shoudlnt": "shouldn't", "coudlnt": "couldn't",
                                   "didtn": "didn't"] {
            XCTAssertEqual(engine.suggestion(in: "it \(source) "), expected, source)
        }
        for source in ["docent", "does", "doest", "would", "should", "could", "did", "donut", "wants", "wonted", "haste", "hasn't", "doesn't"] {
            XCTAssertNil(engine.suggestion(in: "the \(source) "), source)
        }
    }

    func testMoreDamagedLongWordsWithNativeAgreement() {
        for (source, expected) in ["acknolwedgmnt": "acknowledgment", "incomprehenible": "incomprehensible",
                                   "misunderstndng": "misunderstanding", "responsibilty": "responsibility",
                                   "indepndently": "independently", "constutional": "constitutional",
                                   "configuraiton": "configuration", "comunication": "communication",
                                   "thousnads": "thousands", "definitley": "definitely",
                                   "accomodate": "accommodate", "reccomend": "recommend", "neccessary": "necessary"] {
            XCTAssertEqual(engine.suggestion(in: source + " "), expected, source)
        }
    }

    func testCompanySoftwareAndFormatCasing() {
        for (source, expected) in ["powerpoint": "PowerPoint", "photoshop": "Photoshop", "onenote": "OneNote",
                                   "microsoft": "Microsoft", "figma": "Figma", "kubernetes": "Kubernetes",
                                   "typescript": "TypeScript", "javascript": "JavaScript", "salesforce": "Salesforce",
                                   "digitalocean": "DigitalOcean", "mongodb": "MongoDB", "postgresql": "PostgreSQL",
                                   "hashicorp": "HashiCorp", "cloudflare": "Cloudflare", "gitlab": "GitLab",
                                   "nordvpn": "NordVPN", "openai": "OpenAI", "pdf": "PDF", "json": "JSON"] {
            XCTAssertEqual(engine.suggestion(in: "use \(source) "), expected, source)
        }
        XCTAssertGreaterThan(NameLexicon.recognizedTermCount, 6000)
        XCTAssertGreaterThan(NameLexicon.canonicalNameCount, 2000)
    }

    func testNamesWithMissingLettersAndSwaps() {
        for (source, expected) in ["powerpiont": "PowerPoint", "powepoint": "PowerPoint", "microsfot": "Microsoft",
                                   "photoshp": "Photoshop", "photshop": "Photoshop", "figmaa": "Figma",
                                   "kubernets": "Kubernetes", "kuberntees": "Kubernetes", "iphoen": "iPhone"] {
            XCTAssertEqual(engine.suggestion(in: "use \(source) "), expected, source)
        }
        XCTAssertEqual(engine.suggestion(in: "Done. iphoen "), "iPhone")
    }

    func testCommonWordsDoNotBecomeCompaniesOrContractions() {
        for word in ["apple", "word", "excel", "notion", "slack", "zoom", "adobe", "shell", "target", "box", "square",
                     "meta", "oracle", "canon", "dell", "mint", "signal", "opera", "edge", "safari", "chrome",
                     "discord", "steam", "unity", "blender", "sketch", "snap", "epic", "stripe", "buffer", "make",
                     "homebrew", "phone", "siphon", "PowerPoint", "GitHub", "iPhone", "POWERPOINT"] {
            XCTAssertNil(engine.suggestion(in: "my \(word) "), word)
        }
    }

    func testTechnicalRecognitionAndSettingsOverrides() {
        for word in ["figma", "kubernetes", "nginx", "webpack", "homebrew", "docx", "pptx"] {
            preferences.normalizesProductNames = false
            XCTAssertNil(engine.suggestion(in: word + " "), word)
        }
        preferences.normalizesProductNames = true
        preferences.ignoredWords = ["powerpoint", "doenst", "figma"]
        for word in preferences.ignoredWords { XCTAssertNil(engine.suggestion(word), word) }
        preferences.ignoredWords = []
        preferences.customCorrections = ["powerpoint": "my slides", "doenst": "does not", "figma": "FIGMA"]
        for (word, expected) in preferences.customCorrections { XCTAssertEqual(engine.suggestion(word), expected) }
    }

    func testTypingFilenamesAndURLsDoesNotCorrectTheBasenameAtTheDot() {
        for text in ["doenst.txt ", "powerpoint.pptx ", "iphoen.png ", "github.com ", "user@doenst.com ",
                     "/tmp/doenst.txt ", "./powerpoint.pptx ", "powerpoint_file.txt ", "https://github.com "] {
            XCTAssertNil(engine.previewText(in: text), text)
        }
        XCTAssertNil(engine.previewText(in: "doenst."))
        XCTAssertEqual(engine.previewText(in: "it doenst. "), "it doesn't. ")
        XCTAssertEqual(engine.previewText(in: "its ready. "), "it's ready. ")
    }
}
