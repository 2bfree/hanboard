import UIKit
import JapaneseConversion

/// Recreates the Korean two-set arrangement using public UIKit APIs.
/// All key events are handled by the keyboard extension.
final class KeyboardViewController: UIInputViewController {
    private let rows = ["ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ", "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ", "ㅋㅌㅊㅍㅠㅜㅡ"]
    private let numberRows = ["1234567890", "-/:;()¥&@", "。、？！…ー"]
    private var keys: [String: KeyButton] = [:]
    private var katakanaMode = false
    private var symbols = false
    private var raw = ""
    private var markedText = ""
    private var documentID: UUID?
    private var pendingCommit: (task: Task<Void, Never>, suffix: String)?
    private var queuedKeyActions: [() -> Void] = []
    private var heightConstraint: NSLayoutConstraint?
    private var leftContext = ""
    private var isWriting = false

    private lazy var mapper: KanaMapper = {
        let url = Bundle.main.url(forResource: "kana", withExtension: "csv")
        return KanaMapper(csv: url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
    }()
    private lazy var engine = JapaneseContextEngine(
        weightURL: Bundle.main.url(forResource: "zenz-v3-small", withExtension: "gguf")
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        primaryLanguage = "ja-JP"
        buildKeys()
    }

    override func updateViewConstraints() {
        if heightConstraint == nil {
            let constraint = view.heightAnchor.constraint(equalToConstant: 216)
            constraint.priority = .defaultHigh
            constraint.isActive = true
            heightConstraint = constraint
        }
        super.updateViewConstraints()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        syncDocument()
        buildKeys()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutKeys()
    }

    override func viewWillDisappear(_ animated: Bool) {
        syncDocument()
        if let pendingCommit {
            commit(markedText + pendingCommit.suffix)
        } else {
            finishComposition(converting: false)
        }
        super.viewWillDisappear(animated)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if !isWriting { syncDocument() }
        updateColors()
        updateReturnKey()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        guard !isWriting else { return }
        syncDocument()
        if !markedText.isEmpty, let selected = textDocumentProxy.selectedText, !selected.isEmpty {
            abandonComposition()
        }
    }

    private func syncDocument() {
        let id = textDocumentProxy.documentIdentifier
        if let documentID, documentID != id { abandonComposition() }
        documentID = id
    }

    private func abandonComposition() {
        pendingCommit?.task.cancel()
        pendingCommit = nil
        queuedKeyActions.removeAll()
        raw = ""
        markedText = ""
        leftContext = ""
    }

    private func buildKeys() {
        keys.values.forEach { $0.removeFromSuperview() }
        keys.removeAll()
        for (row, labels) in (symbols ? numberRows : rows).enumerated() {
            for (column, label) in labels.enumerated() {
                makeKey("r\(row)c\(column)", text: String(label)) { [weak self] in
                    self?.type(String(label))
                }
            }
        }
        makeKey("shift", image: katakanaMode ? "shift.fill" : "shift", special: true) { [weak self] in
            self?.toggleShift()
        }
        makeKey("delete", image: "delete.left", special: true) { [weak self] in self?.erase() }
        makeKey("symbols", text: symbols ? "한글" : "123", special: true) { [weak self] in
            self?.toggleSymbols()
        }
        if needsInputModeSwitchKey {
            let globe = KeyButton(special: true)
            globe.setImage(UIImage(systemName: "globe"), for: .normal)
            globe.accessibilityLabel = "キーボードを切り替え"
            globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
            view.addSubview(globe)
            keys["globe"] = globe
        }
        makeKey("space", text: "space") { [weak self] in self?.space() }
        makeKey("return", text: "return", special: true) { [weak self] in self?.enter() }
        updateColors()
        updateReturnKey()
        view.setNeedsLayout()
    }

    private func makeKey(_ id: String, text: String? = nil, image: String? = nil,
                         special: Bool = false, action: @escaping () -> Void) {
        let button = KeyButton(special: special)
        if let text {
            button.setTitle(text, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: id.hasPrefix("r") ? 24 : 15)
        }
        if let image { button.setImage(UIImage(systemName: image), for: .normal) }
        button.accessibilityLabel = text ?? image
        if id == "shift" { button.accessibilityLabel = "カタカナ切り替え" }
        if id == "delete" { button.accessibilityLabel = "削除" }
        button.addAction(UIAction { [weak self] _ in self?.handleKeyAction(action) }, for: .touchUpInside)
        view.addSubview(button)
        keys[id] = button
    }

    private func handleKeyAction(_ action: @escaping () -> Void) {
        syncDocument()
        if pendingCommit == nil {
            action()
        } else {
            queuedKeyActions.append(action)
        }
    }

    private func layoutKeys() {
        // Native-style portrait proportions: 10 columns, centered 9-key row,
        // 7 letters between the wider shift and delete keys, wide space bar.
        let width = view.bounds.width
        let height = view.bounds.height
        guard width > 0, height > 0 else { return }
        let inset: CGFloat = 3
        let horizontalGap: CGFloat = 5
        let verticalGap: CGFloat = 10
        let usableWidth = width - inset * 2
        let keyWidth = (usableWidth - horizontalGap * 9) / 10
        let keyHeight = max(24, (height - 10 - verticalGap * 3) / 4)
        let labels = symbols ? numberRows : rows

        func put(_ id: String, _ x: CGFloat, _ row: Int, _ w: CGFloat) {
            keys[id]?.frame = CGRect(x: x.rounded(), y: (5 + CGFloat(row) * (keyHeight + verticalGap)).rounded(),
                                     width: w.rounded(), height: keyHeight.rounded())
        }
        for row in 0...1 {
            let n = CGFloat(labels[row].count)
            let total = n * keyWidth + (n - 1) * horizontalGap
            let start = (width - total) / 2
            for column in labels[row].indices.enumerated() {
                put("r\(row)c\(column.offset)", start + CGFloat(column.offset) * (keyWidth + horizontalGap), row, keyWidth)
            }
        }
        let count = CGFloat(labels[2].count)
        let middleWidth = count * keyWidth + max(0, count - 1) * horizontalGap
        let side = (usableWidth - middleWidth - horizontalGap * 2) / 2
        put("shift", inset, 2, side)
        for column in 0..<Int(count) {
            put("r2c\(column)", inset + side + horizontalGap + CGFloat(column) * (keyWidth + horizontalGap), 2, keyWidth)
        }
        put("delete", width - inset - side, 2, side)

        let small = keyWidth * 1.45
        let returnWidth = keyWidth * 2.5
        var x = inset
        put("symbols", x, 3, small)
        x += small + horizontalGap
        if keys["globe"] != nil {
            put("globe", x, 3, keyWidth)
            x += keyWidth + horizontalGap
        }
        let returnX = width - inset - returnWidth
        put("space", x, 3, max(20, returnX - horizontalGap - x))
        put("return", returnX, 3, returnWidth)
    }

    private func updateColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        view.backgroundColor = dark ? UIColor(white: 0.13, alpha: 1) : UIColor(red: 0.81, green: 0.83, blue: 0.86, alpha: 1)
        keys.forEach { id, button in
            button.applyPalette(dark: dark, active: id == "shift" && katakanaMode)
        }
    }

    private func updateReturnKey() {
        let label: String
        switch textDocumentProxy.returnKeyType {
        case .search: label = "検索"
        case .send: label = "送信"
        case .go: label = "移動"
        case .done: label = "完了"
        case .next: label = "次へ"
        default: label = "return"
        }
        keys["return"]?.setTitle(label, for: .normal)
    }

    private func type(_ key: String) {
        syncDocument()
        if symbols {
            finishComposition(inserting: key)
            return
        }
        if raw.isEmpty {
            leftContext = String((textDocumentProxy.documentContextBeforeInput ?? "").suffix(80))
        }
        raw += key
        render()
    }

    private func toggleShift() {
        guard finishComposition() else { return }
        if symbols { symbols = false }
        katakanaMode.toggle()
        buildKeys()
        UIAccessibility.post(notification: .announcement, argument: katakanaMode ? "カタカナ" : "自動変換")
    }

    private func toggleSymbols() {
        guard finishComposition() else { return }
        symbols.toggle()
        buildKeys()
    }

    private func erase() {
        syncDocument()
        if raw.isEmpty {
            textDocumentProxy.deleteBackward()
        } else {
            raw.removeLast()
            render()
        }
    }

    private func space() {
        finishComposition(inserting: " ")
    }

    private func enter() {
        finishComposition(inserting: "\n")
    }

    /// Do not overwrite committed surrounding text with delete/reinsert.
    /// Only update the host's active marked composition.
    private func writeMarked(_ value: String) {
        isWriting = true
        defer { isWriting = false }
        if value.isEmpty {
            if !markedText.isEmpty {
                textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
                textDocumentProxy.unmarkText()
            }
        } else {
            textDocumentProxy.setMarkedText(value, selectedRange: NSRange(location: value.utf16.count, length: 0))
        }
        markedText = value
    }

    private func render() {
        let parsed = mapper.parse(raw, mode: katakanaMode ? .katakana : .automatic)
        // Incomplete jamo stay in the keyboard buffer; only Japanese reaches the host.
        writeMarked(parsed.kana)
        keys["space"]?.accessibilityHint = parsed.complete ? nil : "未確定の入力があります"
    }

    @discardableResult
    private func finishComposition(inserting suffix: String = "", converting: Bool = true) -> Bool {
        syncDocument()
        let parsed = mapper.parse(raw, mode: katakanaMode ? .katakana : .automatic)
        guard parsed.complete else {
            UIAccessibility.post(notification: .announcement, argument: "未確定の入力を修正してください")
            return false
        }
        guard converting, !katakanaMode, !parsed.kana.isEmpty else {
            commit(parsed.kana + suffix)
            return true
        }

        let proxy = textDocumentProxy
        let document = proxy.documentIdentifier
        let before = proxy.documentContextBeforeInput
        let after = proxy.documentContextAfterInput
        let context = leftContext
        let task = Task { [weak self, engine] in
            let converted = await engine.convert(parsed.kana, leftContext: context)
            guard let self, !Task.isCancelled else { return }
            let current = self.textDocumentProxy
            guard current.documentIdentifier == document,
                  current.documentContextBeforeInput == before,
                  current.documentContextAfterInput == after else {
                self.abandonComposition()
                return
            }

            let queued = self.queuedKeyActions
            self.commit(converted + suffix)
            for action in queued { self.handleKeyAction(action) }
        }
        pendingCommit = (task, suffix)
        return true
    }

    private func commit(_ text: String) {
        isWriting = true
        defer { isWriting = false }
        if !markedText.isEmpty {
            // Clear just the marked range, then commit through the host's normal text entry.
            textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
            textDocumentProxy.unmarkText()
        }
        if !text.isEmpty {
            textDocumentProxy.insertText(text)
        }
        abandonComposition()
    }
}

private final class KeyButton: UIButton {
    let special: Bool
    private var dark = false
    private var active = false

    init(special: Bool) {
        self.special = special
        super.init(frame: .zero)
        layer.cornerRadius = 5
        layer.cornerCurve = .continuous
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 0.30
        adjustsImageWhenHighlighted = false
        imageView?.contentMode = .scaleAspectFit
        tintColor = .label
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool { didSet { paint() } }

    func applyPalette(dark: Bool, active: Bool) {
        self.dark = dark
        self.active = active
        paint()
    }

    private func paint() {
        let normal = dark ? UIColor(white: 0.32, alpha: 1) : .white
        let function = dark ? UIColor(white: 0.23, alpha: 1) : UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1)
        let base = (special && !active) ? function : normal
        backgroundColor = isHighlighted ? (special ? normal : function) : base
        let foreground: UIColor = dark ? .white : .black
        setTitleColor(foreground, for: .normal)
        tintColor = foreground
    }
}
