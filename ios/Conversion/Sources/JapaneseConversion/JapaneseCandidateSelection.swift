import KanaKanjiConverterModuleWithDefaultDictionary

enum JapaneseCandidateSelection {
    private static let pronounReadings: Set<String> = ["コレ", "ソレ", "アレ", "ドレ", "ワタシ", "ボク"]
    private static let weatherWords = ["天気", "気温", "雨", "雪", "暑", "寒"]

    static func spokenTopic(in candidate: Candidate) -> (offset: Int, pronoun: DicdataElement)? {
        var offset = 0
        for (previous, next) in zip(candidate.data, candidate.data.dropFirst()) {
            offset += previous.ruby.count
            // An isolated ワ after a pronoun is eligible; ワ inside a word is left alone.
            if pronounReadings.contains(previous.ruby), next.ruby == "ワ" {
                return (offset, previous)
            }
        }
        return nil
    }

    static func hasTopicParticle(
        matching spokenTopic: (offset: Int, pronoun: DicdataElement), in candidate: Candidate
    ) -> Bool {
        let (offset, pronoun) = spokenTopic
        var position = 0
        for element in candidate.data {
            if position == offset {
                return element.lcid == CIDData.係助詞ハ.cid && element.word.hasPrefix("は")
            }
            // The dictionary also stores some pronouns and は as a single entry.
            if position == offset - pronoun.ruby.count,
               element.ruby == pronoun.ruby + "ハ", element.word == pronoun.word + "は" {
                return true
            }
            position += element.ruby.count
        }
        return false
    }

    static func preferredText(in candidates: [Candidate], best: Candidate) -> String {
        if best.text.hasPrefix("強は"), weatherWords.contains(where: best.text.contains) {
            let weatherReading = "今日" + best.text.dropFirst()
            if let today = candidates.first(where: { $0.text == weatherReading }),
               Float(best.value) - Float(today.value) <= 1 {
                return today.text
            }
        }

        let questionEnding = "はなんですか"
        if best.text.hasSuffix(questionEnding) {
            let kanjiQuestion = best.text.dropLast(questionEnding.count) + "は何ですか"
            if let question = candidates.first(where: { $0.text == kanjiQuestion }) { return question.text }
        }

        return best.text
    }
}
