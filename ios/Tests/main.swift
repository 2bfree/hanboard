import Foundation

let csv = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let mapper = KanaMapper(csv: csv)
let cases: [(String, String)] = [
    ("ㅅㅡㅅㅣ", "すし"), ("ㅅㅜㅅㅣ", "すし"),
    ("ㅇㅣ", "い"), ("ㅣ", "い"), ("ㄴㅐㅋㅗ", "ねこ"),
    ("ㅋㅑㅋㅜ", "きゃく"), ("ㅈㅛ", "じょ"), ("ㅊㅛ", "ちょ"),
    ("ㅎㅗㄴ", "ほん"), ("ㅋㅏㄴㅣ", "かに"), ("ㅋㅏㄴㅇㅣ", "かんい"),
    ("ㅋㅗㄴㄴㅣㅊㅣㅇㅗㅏ", "こんにちわ"),
    ("ㅊㅛㅅㅌㅗ", "ちょっと"), ("ㅊㅛㅈㅌㅗ", "ちょっと"),
    ("ㅊㅛㅌㅌㅗ", "ちょっと"), ("ㄱㅏㅋㅋㅗㅗ", "がっこお"),
    ("ㅁㅏㅅㅌㅔ", "まって"), ("ㅋㅣㅍㅍㅜ", "きっぷ"),
    ("ㅗㅏ", "わ"), ("ㅗㅇㅏ", "おあ"),
    ("ㅇㅗㅏㅌㅏㅅㅣ", "わたし"), ("ㅅㅡㅅㅣㄱㅏㅌㅏㅂㅔㅌㅏㅇㅣ", "すしがたべたい"),
    ("ㅋㅛㅗ", "きょお"), ("ㅇㅗㅂㅏㅅㅏㄴ", "おばさん"), ("ㅇㅗㅂㅏㅏㅅㅏㄴ", "おばあさん")
]
var failures = 0
for (input, expected) in cases {
    let result = mapper.parse(input)
    if result.kana != expected || !result.complete {
        failures += 1
        print("FAIL: \(input) → \(result), expected \(expected)")
    }
}
let katakanaCases = [("ㅅㅡㅅㅣ", "スシ"), ("ㅌㅣ", "ティ"), ("ㅎㅜㅏ", "ファ")]
for (input, expected) in katakanaCases {
    let result = mapper.parse(input, mode: .katakana)
    if result.kana != expected || !result.complete {
        failures += 1
        print("FAIL: \(input) → \(result), expected \(expected)")
    }
}
for input in ["ㅋ", "ㅓ", "ㅅㅣㅕ"] {
    if mapper.parse(input).complete {
        failures += 1
        print("FAIL: expected pending input for \(input)")
    }
}
print("\(cases.count + katakanaCases.count + 3 - failures)/\(cases.count + katakanaCases.count + 3) checks passed")
exit(failures == 0 ? 0 : 1)
