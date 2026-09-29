import XCTest
@testable import AutoCorrect

/// Hand-labeled everyday regression cases, not a population accuracy benchmark.
final class ReleaseAccuracyCorpusTests: XCTestCase {
    func testEverydayTyposInMultipleContexts() {
        let suite = "ReleaseAccuracy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        let engine = CorrectionEngine(preferences: preferences)
        let pairs = [
            "speoll": "spell", "spelll": "spell", "chek": "check", "chekc": "check",
            "autocorect": "autocorrect", "autocorretion": "autocorrection", "acuracy": "accuracy",
            "accurracy": "accuracy", "compatibilty": "compatibility", "compatable": "compatible",
            "compaitbility": "compatibility", "realy": "really", "becuase": "because", "becase": "because",
            "beacuse": "because", "definately": "definitely", "defintely": "definitely", "definetly": "definitely",
            "probaly": "probably", "probablly": "probably", "probabaly": "probably", "probebly": "probably",
            "seperate": "separate", "seperately": "separately", "seperation": "separation",
            "recieve": "receive", "recieved": "received", "receving": "receiving", "beleive": "believe",
            "beleived": "believed", "freind": "friend", "freinds": "friends", "frend": "friend", "wierd": "weird",
            "thier": "their", "thsoe": "those", "enviroment": "environment", "environmnt": "environment",
            "occured": "occurred", "occurence": "occurrence", "necesary": "necessary", "necesarily": "necessarily",
            "embarassing": "embarrassing", "embarrasment": "embarrassment", "tomorow": "tomorrow", "tommorow": "tomorrow",
            "calandar": "calendar", "availble": "available", "avaiable": "available", "instalation": "installation",
            "intallation": "installation", "downlaod": "download", "dowload": "download", "someting": "something",
            "somthing": "something", "everyting": "everything", "everythng": "everything", "withut": "without",
            "wihout": "without", "togehter": "together", "agian": "again", "agan": "again", "actully": "actually",
            "actualy": "actually", "comming": "coming", "goverment": "government", "governemnt": "government",
            "acheive": "achieve", "acheivement": "achievement", "succesful": "successful", "succesfully": "successfully",
            "independant": "independent", "maintainance": "maintenance", "maintenence": "maintenance",
            "adress": "address", "addres": "address", "buisness": "business", "bussiness": "business"
        ]
        for (source, expected) in pairs {
            for prefix in ["", "please check ", "I typed "] {
                var native = ""
                engine.nativeAssessmentObserver = { _, miss, correction, guesses in
                    native = "miss=\(miss) correction=\(correction ?? "nil") guesses=\(guesses)"
                }
                let result = engine.suggestion(in: prefix + source + " ")
                XCTAssertEqual(result, expected, prefix + source + ": " + native)
            }
        }
    }

    func testQuotedAndRichTextWordsUseTheSameSpellingEngine() {
        let suite = "RichTextAccuracy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        let engine = CorrectionEngine(preferences: preferences)
        for (source, expected) in ["speoll ": "spell ", "“speoll” ": "“spell” ", "'speoll' ": "'spell' ",
                                    "‘speoll’ ": "‘spell’ ", "teh\u{a0}": "the\u{a0}",
                                    "teh\u{202f}": "the\u{202f}"] {
            XCTAssertEqual(engine.previewText(in: source), expected, source)
        }
        preferences.ignoredWords = ["speoll"]
        XCTAssertNil(engine.previewText(in: "“speoll” "))
        preferences.ignoredWords = []
        preferences.customCorrections = ["speoll": "my spelling"]
        XCTAssertEqual(engine.previewText(in: "‘speoll’ "), "‘my spelling’ ")
        for text in ["‘speoll.txt’ ", "'github.com' ", "'homebrew' ", "its own ", "‘don't’ ", "dogs’ "] {
            XCTAssertNil(engine.previewText(in: text), text)
        }
    }
}
