import UIKit
import JapaneseConversion

/// Displays the HanBoard keyboard with the familiar Korean two-set key order.
final class KeyboardViewController: UIInputViewController {
    private enum Page {
        case letters, numbers, symbols

        var rows: [String] {
            switch self {
            case .letters: ["ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ", "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ", "ㅋㅌㅊㅍㅠㅜㅡ"]
            case .numbers: ["1234567890", "-/:;()¥&@", "。、？！…ー"]
            case .symbols: ["[]{}#%^*+=", "_\\|~<>€£•", ".,?!'\"”"]
            }
        }
    }

    private var keys: [String: KeyButton] = [:]
    private var katakanaMode = false
    private var page: Page = .letters
    private var deleteRepeat: Task<Void, Never>?
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
        let preferredHeight: CGFloat = traitCollection.verticalSizeClass == .compact ? 174 : 216
        if heightConstraint == nil {
            let constraint = view.heightAnchor.constraint(equalToConstant: preferredHeight)
            constraint.priority = .defaultHigh
            constraint.isActive = true
            heightConstraint = constraint
        }
        heightConstraint?.constant = preferredHeight
        super.updateViewConstraints()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isViewLoaded else { return }
        updateColors()
        view.setNeedsUpdateConstraints()
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
        stopDeleteRepeat()
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
        stopDeleteRepeat()
        keys.values.forEach { $0.removeFromSuperview() }
        keys.removeAll()
        for (row, labels) in page.rows.enumerated() {
            for (column, label) in labels.enumerated() {
                makeKey("r\(row)c\(column)", text: String(label)) { [weak self] in
                    self?.type(String(label))
                }
            }
        }

        if page == .letters {
            let shift = makeKey("shift", image: katakanaMode ? "shift.fill" : "shift", style: .utility) { [weak self] in
                self?.toggleShift()
            }
            shift.accessibilityLabel = "カタカナ切り替え"
            if katakanaMode { shift.accessibilityTraits.insert(.selected) }
        } else {
            makeKey("shift", text: page == .numbers ? "#+=" : "123", style: .utility) { [weak self] in
                self?.toggleShift()
            }
        }

        let delete = makeKey("delete", image: "delete.left", style: .utility) { [weak self] in
            self?.erase()
        }
        delete.accessibilityLabel = "削除"
        delete.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(handleDeleteHold)))

        makeKey("symbols", text: page == .letters ? "123" : "한글", style: .utility) { [weak self] in
            self?.toggleSymbols()
        }
        if needsInputModeSwitchKey {
            let globe = KeyButton(style: .utility)
            globe.setSymbol("globe")
            globe.accessibilityLabel = "キーボードを切り替え"
            globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
            view.addSubview(globe)
            keys["globe"] = globe
        }
        let modeLabel = katakanaMode ? "カタカナ" : "日本語"
        let space = makeKey("space", text: modeLabel, style: .space) { [weak self] in self?.space() }
        space.accessibilityLabel = "空白、HanBoard \(modeLabel)"
        makeKey("return", style: .returnKey) { [weak self] in self?.enter() }
        updateColors()
        updateReturnKey()
        view.setNeedsLayout()
    }

    @discardableResult
    private func makeKey(_ id: String, text: String? = nil, image: String? = nil,
                         style: KeyButton.Style = .letter, action: @escaping () -> Void) -> KeyButton {
        let button = KeyButton(style: style)
        if let text {
            button.setTitle(text, for: .normal)
        }
        if let image { button.setSymbol(image) }
        button.accessibilityLabel = text ?? image
        button.addAction(UIAction { [weak self] _ in self?.handleKeyAction(action) }, for: .touchUpInside)
        view.addSubview(button)
        keys[id] = button
        return button
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
        let width = view.bounds.width
        let height = view.bounds.height
        guard width >= 160, height >= 110 else { return }
        let compact = height < 190
        let inset: CGFloat = 6
        let horizontalGap: CGFloat = 6
        let verticalGap: CGFloat = compact ? 7 : 11
        let topPadding: CGFloat = compact ? 7 : 12
        let bottomPadding: CGFloat = 6
        let usableWidth = width - inset * 2
        let keyWidth = (usableWidth - horizontalGap * 9) / 10
        let keyHeight = (height - topPadding - bottomPadding - verticalGap * 3) / 4
        let labels = page.rows

        func put(_ id: String, _ x: CGFloat, _ row: Int, _ w: CGFloat) {
            keys[id]?.frame = CGRect(x: x, y: topPadding + CGFloat(row) * (keyHeight + verticalGap), width: w, height: keyHeight)
        }
        for row in 0...1 {
            let n = CGFloat(labels[row].count)
            let total = n * keyWidth + (n - 1) * horizontalGap
            let start = (width - total) / 2
            for column in 0..<labels[row].count {
                put("r\(row)c\(column)", start + CGFloat(column) * (keyWidth + horizontalGap), row, keyWidth)
            }
        }
        let count = CGFloat(labels[2].count)
        let middleWidth = count * keyWidth + (count - 1) * horizontalGap
        let outerGap = horizontalGap + min(4, keyWidth * 0.14)
        let side = (usableWidth - middleWidth - outerGap * 2) / 2
        put("shift", inset, 2, side)
        for column in 0..<Int(count) {
            put("r2c\(column)", inset + side + outerGap + CGFloat(column) * (keyWidth + horizontalGap), 2, keyWidth)
        }
        put("delete", width - inset - side, 2, side)

        let returnWidth = (usableWidth - horizontalGap * 2) * 0.24
        let modeWidth = keys["globe"] == nil ? returnWidth : max(keyWidth, returnWidth - keyWidth - horizontalGap)
        var x = inset
        put("symbols", x, 3, modeWidth)
        x += modeWidth + horizontalGap
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
        view.backgroundColor = dark ? UIColor(red: 0.12, green: 0.17, blue: 0.24, alpha: 1)
            : UIColor(red: 0.87, green: 0.91, blue: 0.96, alpha: 1)
        keys.forEach { id, button in
            button.applyPalette(dark: dark, active: page == .letters && id == "shift" && katakanaMode)
        }
    }

    private func updateReturnKey() {
        guard let key = keys["return"] else { return }
        let label: String?
        switch textDocumentProxy.returnKeyType {
        case .search: label = "検索"
        case .send: label = "送信"
        case .go: label = "移動"
        case .done: label = "完了"
        case .next: label = "次へ"
        case .join: label = "参加"
        case .continue: label = "続ける"
        default: label = nil
        }
        key.setTitle(label, for: .normal)
        key.setSymbol(label == nil ? "return" : nil)
        key.accessibilityLabel = label ?? "改行"
    }

    private func type(_ key: String) {
        syncDocument()
        if page != .letters {
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
        switch page {
        case .letters:
            katakanaMode.toggle()
            UIAccessibility.post(notification: .announcement, argument: katakanaMode ? "カタカナ" : "自動変換")
        case .numbers: page = .symbols
        case .symbols: page = .numbers
        }
        buildKeys()
    }

    private func toggleSymbols() {
        guard finishComposition() else { return }
        page = page == .letters ? .numbers : .letters
        buildKeys()
    }

    @objc private func handleDeleteHold(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            handleKeyAction { [weak self] in self?.erase() }
            deleteRepeat = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 95_000_000)
                    guard let self, !Task.isCancelled else { return }
                    if self.pendingCommit == nil { self.erase() }
                }
            }
        case .changed:
            if let key = gesture.view, !key.bounds.contains(gesture.location(in: key)) { stopDeleteRepeat() }
        case .ended, .cancelled, .failed:
            stopDeleteRepeat()
        default:
            break
        }
    }

    private func stopDeleteRepeat() {
        deleteRepeat?.cancel()
        deleteRepeat = nil
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
    enum Style { case letter, utility, space, returnKey }

    let style: Style
    private var dark = false
    private var active = false

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        titleLabel?.font = .systemFont(ofSize: style == .letter ? 23 : 16, weight: style == .letter ? .regular : .medium)
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.65
        adjustsImageWhenHighlighted = false
        imageView?.contentMode = .scaleAspectFit
        tintColor = .label
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSymbol(_ name: String?) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)
        setImage(name.flatMap { UIImage(systemName: $0, withConfiguration: configuration) }, for: .normal)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -3, dy: -3).contains(point)
    }

    override var isHighlighted: Bool { didSet { paint() } }

    func applyPalette(dark: Bool, active: Bool) {
        self.dark = dark
        self.active = active
        paint()
    }

    private func paint() {
        let normal = dark ? UIColor(red: 0.21, green: 0.27, blue: 0.36, alpha: 1) : UIColor(white: 0.99, alpha: 1)
        let utility = dark ? UIColor(red: 0.26, green: 0.34, blue: 0.46, alpha: 1)
            : UIColor(red: 0.78, green: 0.85, blue: 0.94, alpha: 1)
        let accent = dark ? UIColor(red: 0.33, green: 0.50, blue: 0.78, alpha: 1)
            : UIColor(red: 0.19, green: 0.35, blue: 0.62, alpha: 1)
        let emphasized = style == .returnKey || active
        let base = emphasized ? accent : (style == .utility ? utility : normal)
        backgroundColor = isHighlighted ? base.withAlphaComponent(0.70) : base
        let foreground: UIColor = dark || emphasized ? .white : UIColor(red: 0.10, green: 0.16, blue: 0.25, alpha: 1)
        setTitleColor(foreground, for: .normal)
        tintColor = foreground
    }
}
