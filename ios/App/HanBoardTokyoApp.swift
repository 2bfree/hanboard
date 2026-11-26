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
                    TextEditor(text: $text).frame(minHeight: 120)
                    Text("例：ㅅㅡㅅㅣ → すし／寿司")
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
