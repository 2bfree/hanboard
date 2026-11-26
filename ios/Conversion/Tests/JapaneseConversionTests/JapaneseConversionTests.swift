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
