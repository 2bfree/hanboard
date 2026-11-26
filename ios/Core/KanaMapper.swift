import Foundation

/// A draft phonetic parser, not a translation engine. Source: mappings/ja/kana.csv.
struct KanaMapper {
    enum Mode { case automatic, katakana }
    struct Result: Equatable {
        var kana: String
        var pending: String
        var complete: Bool { pending.isEmpty }
    }
    private let native: [String: String]
    private let extensions: [String: String]
    private let vowels = Set("ㅏㅣㅜㅡㅔㅐㅗㅑㅠㅛㅓㅕ")
    private let consonants = Set("ㅂㅈㄷㄱㅅㅁㄴㅇㄹㅎㅋㅌㅊㅍ")
    private let geminates = Set("ㅋㄱㅅㅈㅌㅊㄷㅎㅂㅍ")
    
    init(csv: String) {
        var native: [String: String] = [:]
        var extensions: [String: String] = [:]
        for line in csv.split(whereSeparator: \.isNewline).dropFirst() {
            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 8 else { continue }
            if parts[6] == "native", parts[3] != "nasal" {
                native[parts[0]] = parts[1]
            } else if parts[6] == "katakana_extension" {
                extensions[parts[0]] = parts[1]
            }
        }
        self.native = native
        self.extensions = extensions
    }

    /// The longest match uses explicit ㅇ to disambiguate adjacent vowels.
    /// The nasal and geminate rules are conditional rather than unconditional CSV substitutions.
    func parse(_ input: String, mode: Mode = .automatic) -> Result {
        let keys = Array(input)
        let table = mode == .katakana ? native.merging(extensions, uniquingKeysWith: { _, rhs in rhs }) : native
        var result = ""
        var pending = ""
        var i = 0

        func match(_ at: Int) -> (String, Int)? {
            guard at < keys.count else { return nil }
            for count in stride(from: min(3, keys.count - at), through: 1, by: -1) {
                if let kana = table[String(keys[at..<(at + count)])] {
                    return (kana, count)
                }
            }
            return nil
        }

        while i < keys.count {
            let key = keys[i]
            let next: Character? = i + 1 < keys.count ? keys[i + 1] : nil

            // Prefer syllable onsets: ㄴㅣ is に, while ㄴㅇㅣ is んい.
            if let (kana, count) = match(i) {
                result += kana
                i += count
                continue
            }

            if !result.isEmpty {
                if key == "ㄴ" || key == "ㅁ" || key == "ㅇ" {
                    // ㄴ is canonical; ㅁ/ㅇ are experimental coda aliases.
                    if next == nil || next.map({ consonants.contains($0) }) == true {
                        result += "ん"; i += 1; continue
                    }
                }
                if let next, key == next, geminates.contains(key) {
                    if match(i + 1) != nil {
                        result += "っ"; i += 1; continue
                    }
                }
                if key == "ㅅ" || key == "ㅈ" {
                    // Korean-style coda, e.g. ㅊㅛㅅㅌㅗ → ちょっと.
                    if next == nil || next.map({ consonants.contains($0) }) == true {
                        result += "っ"; i += 1; continue
                    }
                }
            }

            // Keep unresolved keystrokes for editing. Do not silently discard them
            // or convert a suffix while an earlier symbol remains unresolved.
            pending = String(keys[i...])
            break
        }
        if mode == .katakana { result = Self.katakana(result) }
        return Result(kana: result, pending: pending)
    }

    static func katakana(_ kana: String) -> String {
        String(kana.unicodeScalars.map { scalar -> Character in
            if (0x3041...0x3096).contains(scalar.value),
               let converted = UnicodeScalar(scalar.value + 0x60) {
                return Character(String(converted))
            }
            return Character(String(scalar))
        })
    }
}
