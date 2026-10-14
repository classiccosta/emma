@testable import Emma
import XCTest

final class SettingsTests: XCTestCase {
    func testOldSavedSettingsKeepTheirValues() throws {
        // What the previous build saved: only the original keys.
        let old = #"{"endSilence":2,"followUp":6,"modelID":"qwen\/qwen3-4b-2507","noSpeechTimeout":5,"speechSpeed":0.95,"speakReplies":true}"#
        let settings = try Settings.decode(Data(old.utf8))
        XCTAssertEqual(settings.endSilence, 2)
        XCTAssertEqual(settings.speechSpeed, 0.95)
        XCTAssertEqual(settings.addressForm, .sir)
        XCTAssertEqual(settings.jokes, .rarely)
        XCTAssertEqual(settings.phrases, PhraseSettings())
    }

    func testRoundTrip() throws {
        var settings = Settings()
        settings.addressForm = .madam
        settings.phrases.closings = ["Cheers, sir."]
        let decoded = try Settings.decode(JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }

    func testPartialPhrasesAndUnknownKeys() throws {
        let saved = #"{"phrases":{"closings":["Cheers."]},"removedSetting":true}"#
        let settings = try Settings.decode(Data(saved.utf8))
        XCTAssertEqual(settings.phrases.closings, ["Cheers."])
        XCTAssertEqual(settings.phrases.fillers, Phrases.fillers)
    }

    func testNormalizedClampsAndRefills() {
        var settings = Settings()
        settings.endSilence = 99
        settings.maxTokens = 5
        settings.phrases.fillers = ["  ", ""]
        settings.afternoonStart = 3
        let normalized = settings.normalized
        XCTAssertEqual(normalized.endSilence, Settings.endSilenceRange.upperBound)
        XCTAssertEqual(normalized.maxTokens, Settings.maxTokensRange.lowerBound)
        XCTAssertEqual(normalized.phrases.fillers, Phrases.fillers)
        XCTAssertGreaterThan(normalized.afternoonStart, normalized.morningStart)
    }

    func testAddressWord() {
        var settings = Settings()
        XCTAssertEqual(settings.addressWord, "sir")
        settings.addressForm = .custom
        XCTAssertNil(settings.addressWord, "a blank custom word means none")
        settings.customAddress = " boss "
        XCTAssertEqual(settings.addressWord, "boss")
        settings.addressForm = .none
        XCTAssertNil(settings.addressWord)
    }
}

final class PersonaPromptTests: XCTestCase {
    func testDefaultsKeepTheTunedRules() {
        let prompt = PersonaPrompt.build(Settings())
        XCTAssertTrue(prompt.contains(#"Say "sir" only when greeting the user or saying goodbye"#))
        XCTAssertTrue(prompt.contains("Answer in one sentence."))
        XCTAssertTrue(prompt.contains("Never ask if the user wants more detail"))
        XCTAssertTrue(prompt.contains("Never give emotional advice"))
        XCTAssertTrue(prompt.contains("Canberra, not Sydney, which still annoys Sydney."))
    }

    func testNoAddressLeavesNoSir() {
        var settings = Settings()
        settings.addressForm = .none
        let prompt = PersonaPrompt.build(settings)
        XCTAssertFalse(prompt.replacingOccurrences(of: #""sir", "madam""#, with: "").contains("sir"))
    }

    func testMadam() {
        var settings = Settings()
        settings.addressForm = .madam
        let prompt = PersonaPrompt.build(settings)
        XCTAssertTrue(prompt.contains("What can I do for you, madam?"))
        XCTAssertFalse(prompt.contains(", sir"))
    }

    func testNoJokes() {
        var settings = Settings()
        settings.jokes = .never
        let prompt = PersonaPrompt.build(settings)
        XCTAssertTrue(prompt.contains("Never joke."))
        XCTAssertFalse(prompt.contains("which still annoys Sydney"))
    }

    func testLengthAndOffers() {
        var settings = Settings()
        settings.replyLength = .upToTwo
        settings.offerMoreDetail = true
        let prompt = PersonaPrompt.build(settings)
        XCTAssertTrue(prompt.contains("one or two short sentences"))
        XCTAssertFalse(prompt.contains("Never ask if the user wants more detail"))
    }

    func testEmotionalTone() {
        var settings = Settings()
        settings.emotionalTone = .brief
        let prompt = PersonaPrompt.build(settings)
        XCTAssertTrue(prompt.contains("Sorry to hear that."))
        XCTAssertTrue(prompt.contains("Never give emotional advice"))
    }
}

final class AddressFormTests: XCTestCase {
    func testRender() {
        XCTAssertEqual(Address.render("Yes sir?", word: "madam"), "Yes madam?")
        XCTAssertEqual(Address.render("Anytime, sir.", word: nil), "Anytime.")
        XCTAssertEqual(Address.render("One sec.", word: "madam"), "One sec.")
    }

    func testAddresserWithOtherWordAndToggles() {
        var madam = Addresser(word: "madam")
        XCTAssertEqual(madam.adjust("Have a great day, sir."), "Have a great day, madam.")

        var noGreetings = Addresser(word: "sir", inGreetings: false)
        XCTAssertEqual(noGreetings.adjust("What can I do for you, sir?"), "What can I do for you?")
        XCTAssertEqual(noGreetings.adjust("Have a great day."), "Have a great day, sir.")

        var none = Addresser(word: nil)
        XCTAssertEqual(none.adjust("Take care, sir."), "Take care.")
    }

    func testStockRepliesFollowTheSettings() {
        var settings = Settings()
        settings.addressForm = .madam
        settings.addressInGoodbyes = false
        var stock = StockReplies(settings: settings)
        XCTAssertFalse(stock.closing().contains("madam"))
        XCTAssertFalse(stock.closing().contains("sir"))
        XCTAssertTrue(stock.anythingElse.contains("madam"))
        settings.periodGreeting = false
        stock.update(settings)
        XCTAssertNil(stock.periodGreeting())
    }
}

final class DayBoundaryTests: XCTestCase {
    func testCustomBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")! // swiftlint:disable:this force_unwrapping
        let five = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 5, minute: 30))! // swiftlint:disable:this force_unwrapping
        let late = DayBoundaries(morning: 6, afternoon: 12, evening: 18)
        XCTAssertEqual(DayPeriod.key(for: five, boundaries: late, calendar: calendar).period, .evening)
        XCTAssertEqual(DayPeriod.key(for: five, calendar: calendar).period, .morning)
        XCTAssertEqual(DayPeriod.afternoon.greeting(word: nil), "Hello. Good afternoon.")
    }
}
