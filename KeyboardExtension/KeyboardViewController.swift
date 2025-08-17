import UIKit

final class KeyboardViewController: UIInputViewController {
    private let toggleButton = UIButton(type: .system)
    private let applyButton = UIButton(type: .system)
    private let clipboardButton = UIButton(type: .system)
    private let tipLabel = UILabel()

    private let llm = LLMBridge()
    private let local = LocalLLM()
    private let defaults = UserDefaults(suiteName: APP_GROUP_ID)!
    private var useLocal = true // offline-first; can be toggled via settings later

    private var mode: Mode = .enhance { didSet { updateToggleTitle(); saveStickyPreference() } }
    private var style: Style = .formal { didSet { saveStickyPreference() } }
    private var tipUsesRemaining: Int = 5

    private var pill: SuggestionPill?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        wireGestures()
        loadTipCounter()
        loadStickyPreferenceForCurrentContext()
        checkForGeneratedReplySuggestion()
        maybeShowClipboardSuggestion()
        // Enforce offline-only: ignore settings toggle and always prefer local
        useLocal = true
        // Warm-start local model to reduce first-token latency.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.local.initializeIfNeeded() }

        // Temporary debug code - bundle structure and model presence
        if let resourcePath = Bundle.main.resourcePath {
            let resourceURL = URL(fileURLWithPath: resourcePath)
            let fm = FileManager.default

            print("=== BUNDLE DEBUG ===")
            print("Bundle path: \(resourcePath)")

            // Check for model.gguf specifically
            let modelPath = resourceURL.appendingPathComponent("model.gguf")
            print("Looking for model at: \(modelPath.path)")
            print("Model exists: \(fm.fileExists(atPath: modelPath.path))")

            // List all .gguf files
            if let enumerator = fm.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
                var ggufFiles: [String] = []
                for case let url as URL in enumerator {
                    if url.pathExtension.lowercased() == "gguf" {
                        ggufFiles.append(url.path)
                    }
                }
                print("All GGUF files found: \(ggufFiles)")
            }
            print("=== END BUNDLE DEBUG ===")
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Free local model resources if needed
        local.unload()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        toggleButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        applyButton.setTitle("Apply", for: .normal)
        clipboardButton.setTitle("Use Clipboard", for: .normal)

        applyButton.addTarget(self, action: #selector(applyTransform), for: .touchUpInside)
        clipboardButton.addTarget(self, action: #selector(replyFromClipboard), for: .touchUpInside)

        tipLabel.text = "Tap to change"
        tipLabel.font = .systemFont(ofSize: 12)
        tipLabel.alpha = 0.75

        let row = UIStackView(arrangedSubviews: [toggleButton, applyButton, clipboardButton])
        row.axis = .horizontal; row.spacing = 10; row.alignment = .center
        let root = UIStackView(arrangedSubviews: [row, tipLabel])
        root.axis = .vertical; root.spacing = 6; root.alignment = .center
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            root.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        updateToggleTitle(); updateTipVisibility()
    }

    private func wireGestures() {
        let single = UITapGestureRecognizer(target: self, action: #selector(didSingleTapToggle))
        single.numberOfTapsRequired = 1
        let double = UITapGestureRecognizer(target: self, action: #selector(didDoubleTapToggle))
        double.numberOfTapsRequired = 2
        single.require(toFail: double)
        toggleButton.addGestureRecognizer(single)
        toggleButton.addGestureRecognizer(double)

        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(openStylePicker))
        swipeUp.direction = .up
        toggleButton.addGestureRecognizer(swipeUp)

        let long = UILongPressGestureRecognizer(target: self, action: #selector(openStylePicker))
        toggleButton.addGestureRecognizer(long)
    }

    private func updateToggleTitle() {
        toggleButton.setTitle(mode == .enhance ? "Enhance" : "Reply", for: .normal)
    }

    @objc private func didSingleTapToggle() {
        mode = (mode == .enhance) ? .reply : .enhance
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        decrementTip()
    }

    @objc private func didDoubleTapToggle() { openStylePicker() }

    @objc private func openStylePicker() {
        // Keyboard extensions cannot present UIAlertController.
        // Use an inline picker view instead.
        let picker = StylePickerView()
        picker.onSelect = { [weak self] (s: Style) in
            self?.style = s
            self?.decrementTip()
        }
        picker.present(over: self.view)
        decrementTip()
    }

    // MARK: - Tip logic
    private func loadTipCounter() {
        let stored = defaults.object(forKey: TIP_COUNTER_KEY) as? Int
        tipUsesRemaining = stored ?? 5
    }

    private func decrementTip() {
        guard tipUsesRemaining > 0 else { return }
        tipUsesRemaining -= 1
        defaults.set(tipUsesRemaining, forKey: TIP_COUNTER_KEY)
        updateTipVisibility()
    }

    private func updateTipVisibility() { tipLabel.isHidden = (tipUsesRemaining <= 0) }

    // MARK: - Sticky preferences by traits
    private func currentStickyKey() -> StickyKey {
        let t = textDocumentProxy as? UITextInputTraits
        return StickyKey(
            returnKey: t?.returnKeyType?.rawValue ?? UIReturnKeyType.default.rawValue,
            keyboardType: t?.keyboardType?.rawValue ?? UIKeyboardType.default.rawValue,
            autoCap: t?.autocapitalizationType?.rawValue ?? UITextAutocapitalizationType.sentences.rawValue
        )
    }

    private func loadStickyPreferenceForCurrentContext() {
        let key = currentStickyKey()
        if let data = defaults.data(forKey: "sticky.\(key.hashValue)"),
           let pref = try? JSONDecoder().decode(StickyPreference.self, from: data) {
            mode = pref.mode; style = pref.style
        } else {
            if let traits = textDocumentProxy as? UITextInputTraits,
               traits.returnKeyType == .send || traits.returnKeyType == .done {
                mode = .reply
            } else { mode = .enhance }
        }
    }

    private func saveStickyPreference() {
        let key = currentStickyKey()
        let pref = StickyPreference(mode: mode, style: style)
        if let data = try? JSONEncoder().encode(pref) {
            defaults.set(data, forKey: "sticky.\(key.hashValue)")
        }
    }

    // MARK: - Suggestion pills
    private func showPill(_ text: String, action: @escaping () -> Void) {
        pill?.removeFromSuperview()
        let p = SuggestionPill(text: text, action: action)
        p.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(p)
        NSLayoutConstraint.activate([
            p.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            p.topAnchor.constraint(equalTo: view.topAnchor, constant: 6)
        ])
        pill = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.pill?.removeFromSuperview() }
    }

    private func maybeShowClipboardSuggestion() {
        // Accessing UIPasteboard without Full Access can cause "Operation not authorized" logs.
        guard self.hasFullAccess else { return }
        if let s = UIPasteboard.general.string, s.count > 12, s.contains("\n") {
            showPill("Reply from clipboard?", action: { [weak self] in self?.replyFromClipboard() })
        }
    }

    func checkForGeneratedReplySuggestion() {
        if let reply = defaults.string(forKey: "lastGeneratedReply"), !reply.isEmpty {
            showPill("Paste reply?", action: { [weak self] in
                self?.textDocumentProxy.insertText(reply)
                self?.defaults.removeObject(forKey: "lastGeneratedReply")
            })
        }
    }

    // MARK: - Transform actions
    @objc private func applyTransform() {
        guard let proxy = textDocumentProxy as? UITextDocumentProxy else { return }
        let before = proxy.documentContextBeforeInput ?? ""
        let after  = proxy.documentContextAfterInput ?? ""
        let source = (mode == .enhance) ? before : replySource(from: proxy)
        UISelectionFeedbackGenerator().selectionChanged()
        runTransform(source, mode: mode, style: style) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let output):
                    for _ in 0..<before.count { proxy.deleteBackward() }
                    proxy.insertText(output + after)
                case .failure(let err):
                    // Provide clearer guidance when the local model isn't installed yet.
                    if let e = err as NSError?, e.domain == "LLM" && e.code == 1001 {
                        self.presentErrorBanner("Local model not available. Open the KeyboardAI app once to install the bundled GGUF model, then try again.")
                    } else {
                        self.presentErrorBanner("Failed: \(err.localizedDescription)")
                    }
                }
            }
        }
    }

    @objc private func replyFromClipboard() {
        guard self.hasFullAccess else { presentErrorBanner("Enable Full Access in Keyboard settings to use the clipboard"); return }
        guard let s = UIPasteboard.general.string, !s.isEmpty else { presentErrorBanner("Clipboard is empty"); return }
        let cleaned = stripQuotesAndSigs(s)
        runTransform(cleaned, mode: .reply, style: style) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let out): self.textDocumentProxy.insertText(out)
                case .failure(let e):   self.presentErrorBanner("Reply failed: \(e.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Helpers
    private func replySource(from proxy: UITextDocumentProxy) -> String {
        let before = proxy.documentContextBeforeInput ?? ""
        let raw = before.split(separator: "\n", omittingEmptySubsequences: false).suffix(20).joined(separator: "\n")
        return stripQuotesAndSigs(raw)
    }

    private func stripQuotesAndSigs(_ text: String) -> String {
        var t = text
        t = t.replacingOccurrences(of: "^On .+ wrote:$", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "^>.*$", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?s)--\\s*\n.*$", with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func presentErrorBanner(_ msg: String) {
        let label = UILabel()
        label.text = msg
        label.font = .systemFont(ofSize: 12)
        label.backgroundColor = .systemRed.withAlphaComponent(0.15)
        label.layer.cornerRadius = 6
        label.layer.masksToBounds = true
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.9)
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { label.removeFromSuperview() }
    }

    // MARK: - Routing: local first, fallback to server
    private func runTransform(_ input: String, mode: Mode, style: Style, completion: @escaping (Result<String, Error>) -> Void) {
        if useLocal {
            let prompt = PromptBuilder.prompt(text: input, mode: mode, style: style)
            local.generate(prompt: prompt, maxTokens: (mode == .reply ? 160 : 100), temp: 0.6, topK: 40, topP: 0.9) { [weak self] res in
                switch res {
                case .success(let s): completion(.success(s))
                case .failure:
                    // Offline-only mode: do not fallback to server
                    completion(.failure(NSError(domain: "LLM", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Local model unavailable"])) )
                }
            }
        } else {
            llm.transform(text: input, mode: mode, style: style, completion: completion)
        }
    }
}
