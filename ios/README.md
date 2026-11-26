# HanBoard Tokyo — iOS keyboard prototype

BeFRee Project · HanBoard

## What this is

A real iOS custom-keyboard extension and its setup app. The keyboard uses the Korean two-set letter positions, a centered middle row, Shift and Delete, 123, space and Return. HanBoard uses a blue palette and labels the space bar with the active Japanese input mode. It has no candidate row. The globe is shown only when iOS requests it; Face ID devices normally provide one below the keyboard. The palette has light and dark appearances.

This is an initial prototype with keyboard input verified on the iPhone simulator and on a physical iPhone 17 Pro. The system keyboard itself is not exposed for embedding by third-party extensions.

## Build on a Mac

Requirements: Xcode with Swift 6.1 or later (Xcode 26 recommended), an iOS 16+ simulator or device, and XcodeGen.

```sh
git clone https://github.com/2bfree/hanboard.git
cd hanboard
brew install xcodegen
cd ios
xcodegen generate
open HanBoardTokyo.xcodeproj
```

In Xcode select the HanBoardTokyo scheme and let Xcode resolve the Swift packages. For physical-device testing, sign in under Xcode → Settings → Apple Accounts. In Signing & Capabilities, use automatic signing and the same team for `HanBoardTokyo` and `HanBoardKeyboard`. If the default bundle identifiers are unavailable, choose a unique identifier for the app and append `.keyboard` for the extension. Select the paired iPhone as the run destination, enable Developer Mode on the iPhone if Xcode asks, and run the app.

On the iPhone, open Settings → General → Keyboard → Keyboards → Add New Keyboard → HanBoard Tokyo. Select it with the system globe key in the app's text editor or Notes.

No Full Access is requested. The app does not transmit typed text or use the microphone. The extension relies on publicly documented UIKit APIs.

## Input behavior

- All 26 modern jamo retain their original positions. No archaic characters, dedicated punctuation keys, flick input, or translation.
- Default mode shows hiragana while typing. Return or Space converts the whole pending reading once and commits it with the selected separator. Use Return after finishing a sentence, or Space to finish a shorter phrase.
- Shift toggles forced katakana in the letter layout. The space bar shows `日本語` or `カタカナ` for the current mode.
- Shift and 123 finish the current reading before switching layouts. In the number layout, `#+=` opens the second symbol page. Delete first removes a pending jamo and repeats while held.
- The setup app's test editor can copy all text or append clipboard text with the system paste button.
- Unresolved jamo are kept internally; committing an unresolved sequence is blocked. For example, ㅓ and ㅕ remain on the keyboard without a mapping.
- The root `mappings/ja/kana.csv` is bundled directly. No duplicate dictionary.
- ㅅㅡㅅㅣ → すし; ㅊㅛㅅㅌㅗ → ちょっと; ㅋㅏㄴㅇㅣ → かんい. These are kana parser expectations, not measured contextual conversion results.
- ㄴ/ㅁ/ㅇ coda aliases and ㅅ/ㅈ coda or repeated-consonant handling are provisional.
- ㅇ explicitly separates an adjacent vowel, e.g. ㅗㅇㅏ → おあ, versus ㅗㅏ → わ.

## Japanese conversion

`Conversion` is a local Swift package that pins AzooKeyKanaKanjiConverter **v0.11.2**. The adapter runs conversion on an actor, disables prediction and persistent learning, and only accepts a candidate whose reading matches the input. The keyboard submits a single request when the user finishes a reading and rejects results for an expired insertion point.

The default build uses the offline dictionary converter. The Zenzai adapter is provided but the neural model is **not enabled by default**. In the extension, actual available memory, speed, and model rights must be checked before enabling it.

The [conversion case log](../docs/conversion-cases.md) records observed errors and their fixes. Run the dictionary regression suite with `swift test --package-path ios/Conversion` from the repository root.

The adapter requests the v3 left-context format documented by AzooKey. The upstream [zenz-v3-small Q5_K_M](https://huggingface.co/Miwa-Keita/zenz-v3-small-gguf) is a 72.3 MB file and is the first candidate for a device benchmark. [Zenzai Plus F16](https://huggingface.co/soichi1208/zenzai-plus) is a 192 MB derivative of zenz-v2.5-small. Validate its prompt format and converter compatibility before using it with this adapter. Both model cards list CC BY-SA 4.0.

To experiment on a Mac:
1. Review the model's license: https://huggingface.co/Miwa-Keita/zenz-v3-small-gguf
2. Place a compatible model file at `ios/ModelWeights/zenz-v3-small.gguf` (do not commit it).
3. In `ios/Conversion/Package.swift`, set `enableZenzai = true`. Regenerate the Xcode project and test the CPU trait and C++ interoperability requirements.
4. Measure peak memory and input latency before enabling this on a physical iPhone. Revert to the dictionary-only build if needed.

Upstream documentation:
- https://github.com/azooKey/AzooKeyKanaKanjiConverter/tree/v0.11.2
- https://github.com/azooKey/AzooKeyKanaKanjiConverter/blob/v0.11.2/Docs/zenzai.md
- https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard
- https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards

## Parser checks (no Xcode or upstream dependencies)

Run from the repository root:

```sh
swiftc ios/Core/KanaMapper.swift ios/Tests/main.swift -o /tmp/hanboard-kana-tests
/tmp/hanboard-kana-tests mappings/ja/kana.csv
```

## Verification so far

- **31/31 parser checks passed** against the checked-in mapping CSV on macOS and Linux.
- XcodeGen 2.49.0 generated the project without Zenzai weights. Xcode 27.2 resolved the Swift packages, built the app and keyboard extension, and installed the app on the iPhone 18 Pro simulator. The extension bundle contains the mapping CSV and dictionary.
- On the iPhone 18 Pro simulator, `すしです` stayed in hiragana while typing and became `寿司です` on Return. Shift produced `スシ`, which Space committed without changing the earlier line. The editor copied and pasted both lines together.
- On a physical iPhone 17 Pro, the keyboard produced `ありがとう`, `寿司が食べたい`, `ちょっと待って`, `東京`, `こんにちは` and `カメラ`. The tests also found incorrect conversions `強はいい天気です` for `今日はいい天気です` and `これ羽なんですか` for `これは何ですか`. Number and symbol switching, Japanese question mark entry and repeated deletion worked on the same build.

## Remaining work

- Measure extension memory usage on physical iPhones.
- Measure the first keyboard launch on a physical device. The simulator sometimes displayed a system keyboard on the first selection after reinstalling the app. Selecting HanBoard again loaded the extension.
- Verify marked-text lifecycle and safe cursor movement across host apps, key previews, orientation, accessibility and dynamic return behavior.
- Native-like geometry is a first approximation, not pixel-identical to any iOS version. Compare actual iPhone light/dark screenshots; no candidate row is a deliberate design difference.
- Complete the phonetic rules for long-vowel spelling, particles は/へ/を, foreign sounds, and resolving ambiguous sequences. Current parser preserves vowel length but does not automatically restore every spelling. Basic dictionary conversion only works on the reading it receives.
- Add correction/undo and forced hiragana/rare kana handling without a permanent candidate list. The prototype does not yet implement automatic punctuation.
- Validate real user transcription data, model licenses and upstream notices before release.
