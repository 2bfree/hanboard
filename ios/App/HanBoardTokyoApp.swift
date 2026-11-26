import SwiftUI

@main
struct HanBoardTokyoApp: App {
    var body: some Scene {
        WindowGroup { SetupView() }
    }
}

private struct SetupView: View {
    @State private var text = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ㅎ").font(.system(size: 52, weight: .medium))
                        Text("HanBoard Tokyo").font(.largeTitle.bold())
                        Text("One Alphabet. Many Languages.")
                        Text("BeFRee Project").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                Section("キーボードの設定") {
                    Text("設定 → 一般 → キーボード → キーボード → 新しいキーボードを追加 → HanBoard Tokyo")
                    Button("設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    Text("フルアクセスは必要ありません。入力は端末内で処理します。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("入力テスト") {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .accessibilityLabel("入力テスト")
                    HStack {
                        Button("すべてコピー") { UIPasteboard.general.string = text }
                            .disabled(text.isEmpty)
                        Spacer()
                        PasteButton(payloadType: String.self) { items in
                            text += items.joined(separator: "\n")
                        }
                        .accessibilityHint("入力欄の末尾に追加します")
                    }
                    .buttonStyle(.borderless)
                    Text("例：ㅅㅡㅅㅣ → すし。改行または空白で変換・確定すると「寿司」になります。")
                    Text("⇧：カタカナモードに切り替え")
                    Button("クリア") { text = "" }
                }
                Section("開発中のバージョン") {
                    Text("v0.1 — 発音入力と日本語変換の試作版です。")
                }
            }
            .navigationTitle("HanBoard")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
