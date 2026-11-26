import KanaKanjiConverterModuleWithDefaultDictionary

enum JapaneseObjectParticle {
    static func restore(
        in reading: String, candidates: [Candidate], convert: (String) -> [Candidate]
    ) -> [Candidate] {
        var characters = Array(reading)
        guard characters.count >= 3 else { return candidates }
        var offsets = characters.indices.dropFirst().dropLast().filter { characters[$0] == "お" }
        var current = candidates
        var minimumGain: Float = 2.5
        // Bound dictionary work when a passage contains several possible particles.
        var remainingRequests = 6

        while !offsets.isEmpty, remainingRequests > 0, let baseline = current.first {
            var best: (offset: Int, candidates: [Candidate], score: Float)?
            for offset in offsets {
                guard remainingRequests > 0, !Task.isCancelled else { break }
                remainingRequests -= 1
                characters[offset] = "を"
                let proposedReading = String(characters)
                let proposed = convert(proposedReading)
                characters[offset] = "お"

                let minimumScore = Float(baseline.value) + minimumGain
                guard let top = proposed.first, top.text != proposedReading,
                      hasWrittenParticle(at: offset, in: top), Float(top.value) >= minimumScore,
                      Float(top.value) > (best?.score ?? -.infinity) else { continue }
                let matching = proposed.filter {
                    $0.text != proposedReading && hasWrittenParticle(at: offset, in: $0)
                }
                let preferred = preservingOtherWords(in: matching, original: baseline, at: offset,
                                                     minimumScore: minimumScore) ?? top
                best = (offset, [preferred] + matching.filter { $0.text != preferred.text }, Float(top.value))
            }
            guard let best else { break }
            characters[best.offset] = "を"
            offsets.removeAll { $0 == best.offset }
            current = best.candidates
            // A second inferred particle needs stronger evidence, especially in phonetic long vowels.
            minimumGain = 8
        }
        return current
    }

    private static func hasWrittenParticle(at offset: Int, in candidate: Candidate) -> Bool {
        guard let (entry, local, _) = segment(at: offset, in: candidate) else { return false }
        // A dictionary entry may contain the particle together with its noun or verb.
        let preceding = entry.ruby.prefix(local).filter { $0 == "ヲ" }.count
        return entry.word.filter { $0 == "を" }.count > preceding
    }

    private static func preservingOtherWords(
        in candidates: [Candidate], original: Candidate, at offset: Int, minimumScore: Float
    ) -> Candidate? {
        guard original.data.map(\.word).joined() == original.text,
              let (entry, local, textOffset) = segment(at: offset, in: original) else { return nil }
        let spoken = entry.ruby.filter { $0 == "オ" }.count
        let surface = entry.word.enumerated().filter { $0.element == "お" }
        guard surface.count == spoken else { return nil }
        let occurrence = entry.ruby.prefix(local).filter { $0 == "オ" }.count
        guard surface.indices.contains(occurrence) else { return nil }
        let position = textOffset + surface[occurrence].offset
        let expected = original.text.prefix(position) + "を" + original.text.dropFirst(position + 1)
        return candidates.first { $0.text == expected && Float($0.value) >= minimumScore }
    }

    private static func segment(
        at offset: Int, in candidate: Candidate
    ) -> (entry: DicdataElement, local: Int, textOffset: Int)? {
        var readingOffset = 0
        var textOffset = 0
        for entry in candidate.data {
            let next = readingOffset + entry.ruby.count
            if offset < next { return (entry, offset - readingOffset, textOffset) }
            readingOffset = next
            textOffset += entry.word.count
        }
        return nil
    }
}
