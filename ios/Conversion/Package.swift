// swift-tools-version: 6.1
import PackageDescription

// Start with the dictionary-only converter. Enable the neural trait after
// measuring extension memory and checking the selected model's license.
let enableZenzai = false
let package = Package(
    name: "JapaneseConversion",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "JapaneseConversion", targets: ["JapaneseConversion"])],
    dependencies: [
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter",
                 exact: "0.11.2", traits: enableZenzai ? ["ZenzaiCPU"] : [])
    ],
    targets: [
        .target(
            name: "JapaneseConversion",
            dependencies: [
                .product(name: "KanaKanjiConverterModuleWithDefaultDictionary",
                         package: "AzooKeyKanaKanjiConverter")
            ],
            swiftSettings: enableZenzai
                ? [.define("HANBOARD_ZENZAI"), .interoperabilityMode(.Cxx)]
                : []
        ),
        .testTarget(name: "JapaneseConversionTests", dependencies: ["JapaneseConversion"])
    ],
    swiftLanguageModes: [.v5]
)
