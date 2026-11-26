# HanBoard Tokyo — iOS keyboard prototype

BeFRee Project · HanBoard

## What this is

A real iOS custom-keyboard extension and its setup app, not an in-app translation keyboard.
The visual target is Apple's Korean two-set keyboard: the same 26 letter positions, white keys on a gray surface, centered middle row, Shift and Delete, 123, space and return. No custom branding or kana candidate row above the keyboard. The globe is shown only when iOS requests it; Face ID devices normally provide one below the keyboard. Dark appearance is supported by the palette.

This is an initial source-code prototype. It has not yet been built with Xcode or tested on an iPhone. The system keyboard itself is not exposed for embedding or exact reuse by third-party extensions.

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

In Xcode select the HanBoardTokyo scheme. Resolve Swift packages; select your signing team for both targets for device installation, and adjust the bundle identifiers if needed. Run the app, then open Settings → General → Keyboard → Keyboards → Add New Keyboard → HanBoard Tokyo. Select it with the system globe key. Test using the app's text editor or Notes.

No Full Access is requested. The app does not transmit typed text or use the microphone. The extension relies on publicly documented UIKit APIs.

## Input behavior

- All 26 modern jamo retain their original positions. No archaic characters, dedicated punctuation keys, flick input, or translation.
- Default mode: input jamo → kana → top full-reading dictionary conversion result, updated inside the active marked text.
- Shift toggles forced katakana and keeps the same jamo labels. It is not the Korean doubled-consonant modifier.
- 123 switches to numbers/symbols; space and return commit the visible composition and insert the respective character. Delete first removes a pending jamo.
- Unresolved jamo are kept internally; committing an unresolved sequence is blocked. For example, ㅓ and ㅕ remain on the keyboard without a mapping.
- The root `mappings/ja/kana.csv` is bundled directly. No duplicate dictionary.
- ㅅㅡㅅㅣ → すし; ㅊㅛㅅㅌㅗ → ちょっと; ㅋㅏㄴㅇㅣ → かんい. These are kana parser expectations, not measured contextual conversion results.
- ㄴ/ㅁ/ㅇ coda aliases and ㅅ/ㅈ coda or repeated-consonant handling are provisional.
- ㅇ explicitly separates an adjacent vowel, e.g. ㅗㅇㅏ → おあ, versus ㅗㅏ → わ.

## Japanese conversion

`Conversion` is a local Swift package that pins AzooKeyKanaKanjiConverter **v0.11.2**. The adapter runs conversion on an actor, disables prediction and persistent learning, and only accepts a candidate whose reading matches the input. The keyboard debounces requests and rejects stale results.

The default build uses the offline dictionary converter. The Zenzai adapter is provided but the neural model is **not enabled by default**. In the extension, actual available memory, speed, and model rights must be checked before enabling it.

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

## Remaining work

- Verify the Xcode project generation, Swift package resolution and real iOS build, signing, device installation and memory usage.
- Verify marked-text lifecycle and safe cursor movement across host apps; long-press keyboard switching, deletion repeat, native-style key previews, numeric keyboard variants, orientation, accessibility and dynamic return behavior.
- Native-like geometry is a first approximation, not pixel-identical to any iOS version. Compare actual iPhone light/dark screenshots; no candidate row is a deliberate design difference.
- Complete the phonetic rules for long-vowel spelling, particles は/へ/を, foreign sounds, and resolving ambiguous sequences. Current parser preserves vowel length but does not automatically restore every spelling. Basic dictionary conversion only works on the reading it receives.
- Add correction/undo and forced hiragana/rare kana handling without a permanent candidate list. The prototype does not yet implement automatic punctuation.
- Validate real user transcription data, model licenses and upstream notices before release.
