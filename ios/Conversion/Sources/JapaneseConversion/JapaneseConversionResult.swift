import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

public struct JapaneseConversionResult: Sendable {
    public let text: String
    public let corrections: [JapaneseCorrection]

    init(text: String, corrections: [JapaneseCorrection]) {
        self.text = text
        self.corrections = corrections
    }

    init(preferredText: String, candidates: [Candidate]) {
        guard let preferred = candidates.first(where: { $0.text == preferredText }),
              preferred.data.map(\.word).joined() == preferredText else {
            self.init(text: preferredText, corrections: [])
            return
        }

        var offset = 0
        var corrections: [JapaneseCorrection] = []
        for entry in preferred.data {
            let range = offset..<(offset + entry.word.count)
            offset = range.upperBound
            let word = entry.word
            guard let firstKanji = word.firstIndex(where: Self.containsKanji),
                  let lastKanji = word.lastIndex(where: Self.containsKanji) else { continue }
            let reading = entry.ruby.applyingTransform(.hiraganaToKatakana, reverse: true) ?? entry.ruby
            let prefix = String(preferredText.prefix(range.lowerBound))
            let suffix = String(preferredText.dropFirst(range.upperBound))
            let otherForms = candidates.compactMap {
                Self.middle(of: $0.text, after: prefix, before: suffix)
            }
            if let correction = JapaneseCorrection(range: range, word: word, forms: otherForms, reading: reading) {
                corrections.append(correction)
            }

            // Dictionary entries can include adjacent kana, such as 天気です.
            // Offer a correction for the kanji portion only when that kana
            // can also be matched exactly in the reading and alternatives.
            let leadingKana = String(word[..<firstKanji])
            let trailingKana = String(word[word.index(after: lastKanji)...])
            guard !leadingKana.isEmpty || !trailingKana.isEmpty,
                  let kanji = Self.middle(of: word, after: leadingKana, before: trailingKana),
                  let kanjiReading = Self.middle(of: reading, after: leadingKana, before: trailingKana) else { continue }
            let kanjiRange = (range.lowerBound + leadingKana.count)..<(range.upperBound - trailingKana.count)
            let kanjiForms = otherForms.compactMap { Self.middle(of: $0, after: leadingKana, before: trailingKana) }
            if let correction = JapaneseCorrection(range: kanjiRange, word: kanji, forms: kanjiForms, reading: kanjiReading) {
                corrections.append(correction)
            }
        }
        self.init(text: preferredText, corrections: corrections)
    }

    public func correction(for selection: String, before: String, after: String) -> JapaneseCorrection? {
        let matches = corrections.filter { correction in
            selection == correction.word &&
                before.hasSuffix(text.prefix(correction.range.lowerBound)) &&
                after.hasPrefix(text.dropFirst(correction.range.upperBound))
        }
        return matches.count == 1 ? matches.first : nil
    }

    public func replacing(_ correction: JapaneseCorrection, with replacement: String) -> Self {
        guard corrections.contains(correction), correction.alternatives.contains(replacement) else { return self }
        let prefix = text.prefix(correction.range.lowerBound)
        let suffix = text.dropFirst(correction.range.upperBound)
        let delta = replacement.count - correction.range.count
        let updated = corrections.compactMap { entry -> JapaneseCorrection? in
            if entry == correction {
                let forms = [entry.word] + entry.alternatives
                let range = entry.range.lowerBound..<(entry.range.upperBound + delta)
                return JapaneseCorrection(range: range, word: replacement, alternatives: forms.filter { $0 != replacement })
            }
            if entry.range.overlaps(correction.range) { return nil }
            let range = entry.range.lowerBound >= correction.range.upperBound
                ? (entry.range.lowerBound + delta)..<(entry.range.upperBound + delta) : entry.range
            return JapaneseCorrection(range: range, word: entry.word, alternatives: entry.alternatives)
        }
        return Self(text: prefix + replacement + suffix, corrections: updated)
    }

    private static func containsKanji(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.isIdeographic }
    }

    private static func middle(of text: String, after prefix: String, before suffix: String) -> String? {
        guard text.count > prefix.count + suffix.count, text.hasPrefix(prefix), text.hasSuffix(suffix) else {
            return nil
        }
        return String(text.dropFirst(prefix.count).dropLast(suffix.count))
    }
}

public struct JapaneseCorrection: Equatable, Sendable {
    public let word: String
    public let alternatives: [String]
    let range: Range<Int>

    fileprivate init(range: Range<Int>, word: String, alternatives: [String]) {
        self.range = range
        self.word = word
        self.alternatives = alternatives
    }

    fileprivate init?(range: Range<Int>, word: String, forms: [String], reading: String) {
        let katakana = reading.applyingTransform(.hiraganaToKatakana, reverse: false) ?? reading
        var seen: Set<String> = [word, reading, katakana]
        var alternatives = Array(forms.filter { seen.insert($0).inserted }.prefix(3))
        if reading != word { alternatives.append(reading) }
        guard !alternatives.isEmpty else { return nil }
        self.init(range: range, word: word, alternatives: alternatives)
    }
}
