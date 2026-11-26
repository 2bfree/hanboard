import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

/// Keep the converter isolated from the keyboard UI. No network, no prediction
/// of untyped words, no persistent learning or text logging.
public actor JapaneseContextEngine {
    private var converter: KanaKanjiConverter?
    private let weightURL: URL?
    private let storage: URL

    public init(weightURL: URL? = nil) {
        self.weightURL = weightURL
        storage = FileManager.default.temporaryDirectory.appendingPathComponent("HanBoardTokyo", isDirectory: true)
    }

    public func convert(_ reading: String, leftContext: String = "") -> String {
        conversion(for: reading, leftContext: leftContext).text
    }

    public func conversion(for reading: String, leftContext: String = "") -> JapaneseConversionResult {
        let unconverted = JapaneseConversionResult(text: reading, corrections: [])
        guard !reading.isEmpty, !Task.isCancelled else { return unconverted }
        try? FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        if converter == nil { converter = KanaKanjiConverter.withDefaultDictionary() }
        guard let converter else { return unconverted }
        var mode: ConvertRequestOptions.ZenzaiMode = .off
        #if HANBOARD_ZENZAI
        if let weightURL, FileManager.default.fileExists(atPath: weightURL.path) {
            mode = .on(weight: weightURL, inferenceLimit: 1,
                       requestRichCandidates: false, personalizationMode: nil,
                       versionDependentMode: .v3(.init(leftSideContext: String(leftContext.suffix(80)))))
        }
        #endif

        let options = ConvertRequestOptions(
            N_best: 5,
            needTypoCorrection: false,
            requireJapanesePrediction: false,
            requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP,
            learningType: .nothing,
            maxMemoryCount: 0,
            memoryDirectoryURL: storage,
            sharedContainerURL: storage,
            textReplacer: .withDefaultEmojiDictionary(),
            specialCandidateProviders: [],
            zenzaiMode: mode,
            metadata: .init(versionString: "HanBoard Tokyo 0.1")
        )
        let candidates = fullCandidates(for: reading, using: converter, options: options)
        guard let best = candidates.first else { return unconverted }
        guard case .off = mode else {
            return JapaneseConversionResult(preferredText: best.text, candidates: candidates)
        }

        if let spokenTopic = JapaneseCandidateSelection.spokenTopic(in: best),
           let index = reading.index(reading.startIndex, offsetBy: spokenTopic.offset, limitedBy: reading.endIndex),
           index < reading.endIndex, reading[index] == "わ" {
            var writtenReading = reading
            writtenReading.replaceSubrange(index...index, with: "は")
            let writtenCandidates = fullCandidates(for: writtenReading, using: converter, options: options)
            if let topic = writtenCandidates.first,
               Float(topic.value) >= Float(best.value) + 4,
               JapaneseCandidateSelection.hasTopicParticle(matching: spokenTopic, in: topic) {
                let preferred = JapaneseCandidateSelection.preferredText(in: writtenCandidates, best: topic)
                return JapaneseConversionResult(preferredText: preferred, candidates: writtenCandidates)
            }
        }

        let preferred = JapaneseCandidateSelection.preferredText(in: candidates, best: best)
        return JapaneseConversionResult(preferredText: preferred, candidates: candidates)
    }

    private func fullCandidates(for reading: String, using converter: KanaKanjiConverter,
                                options: ConvertRequestOptions) -> [Candidate] {
        converter.stopComposition()
        var composition = ComposingText()
        composition.insertAtCursorPosition(reading, inputStyle: .direct)
        let results = converter.requestCandidates(composition, options: options)
        // Do not auto-insert a partial or predictive result.
        let expectedRuby = reading.applyingTransform(.hiraganaToKatakana, reverse: false) ?? reading
        return results.mainResults.filter {
            $0.inputable && !$0.text.isEmpty &&
            $0.data.map(\.ruby).joined() == expectedRuby
        }
    }
}
