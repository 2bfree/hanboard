import JapaneseConversion
import XCTest

final class JapaneseConversionTests: XCTestCase {
    func testPrefersTodayInWeatherSentence() async {
        let engine = JapaneseContextEngine()
        let result = await engine.convert("きょうはいいてんきです")
        XCTAssertEqual(result, "今日はいい天気です")
    }

    func testRestoresSpokenTopicParticleInQuestions() async {
        let engine = JapaneseContextEngine()
        for reading in ["これわなんですか", "これはなんですか"] {
            let result = await engine.convert(reading)
            XCTAssertEqual(result, "これは何ですか", reading)
        }
    }

    func testRestoresSpokenTopicParticleAfterPersonalPronoun() async {
        let engine = JapaneseContextEngine()
        let result = await engine.convert("ぼくわがくせいです")
        XCTAssertEqual(result, "僕は学生です")
    }

    func testCorrectsOnlySelectedKanjiUsingTheOriginalReading() async throws {
        let conversion = await JapaneseContextEngine().conversion(for: "はしでたべます")
        XCTAssertEqual(conversion.text, "橋で食べます")
        let correction = try XCTUnwrap(conversion.correction(for: "橋", before: "", after: "で食べます"))
        XCTAssertEqual(correction.alternatives, ["箸", "はし"])
        XCTAssertNil(conversion.correction(for: "橋", before: "", after: "を渡ります"))
        XCTAssertNil(conversion.correction(for: "橋で", before: "", after: "食べます"))
        XCTAssertEqual(conversion.replacing(correction, with: "箸").text, "箸で食べます")

        let kana = conversion.replacing(correction, with: "はし")
        XCTAssertEqual(kana.text, "はしで食べます")
        let undo = try XCTUnwrap(kana.correction(for: "はし", before: "", after: "で食べます"))
        XCTAssertEqual(undo.alternatives, ["橋", "箸"])
    }

    func testCanCorrectKanjiWithoutTouchingKanaInTheSameDictionaryEntry() async throws {
        let conversion = await JapaneseContextEngine().conversion(for: "きょうはいいてんきです")
        let correction = try XCTUnwrap(conversion.correction(for: "天気", before: "今日はいい", after: "です"))
        XCTAssertTrue(correction.alternatives.contains("てんき"))
        XCTAssertEqual(conversion.replacing(correction, with: "てんき").text, "今日はいいてんきです")
    }

    func testPreservesWordReadingsAndExistingConversions() async {
        let engine = JapaneseContextEngine()
        let cases = [
            ("わたし", "私"),
            ("これわたしのです", "これ私のです"),
            ("これわりざんです", "これわり算です"),
            ("これははねです", "これは羽です"),
            ("きょう", "強"),
            ("すしがたべたい", "寿司が食べたい"),
            ("こんにちわ", "こんにちは")
        ]
        for (reading, expected) in cases {
            let result = await engine.convert(reading)
            XCTAssertEqual(result, expected, reading)
        }
    }
}
