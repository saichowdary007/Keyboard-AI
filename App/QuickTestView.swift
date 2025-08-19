import SwiftUI

// Temporary shim to tolerate older references using a misspelled symbol.
// This allows `taaQuickTestView()` call sites to resolve to `QuickTestView()`.
typealias taaQuickTestView = QuickTestView

struct QuickTestView: View {
    @State private var input: String = ""
    @State private var output: String = ""
    @State private var isGenerating: Bool = false
    @State private var mode: Mode = .enhance
    @State private var style: Style = .formal

    private let local = LocalLLM()
    private let bridge = LLMBridge()
    private let defaults = UserDefaults(suiteName: APP_GROUP_ID)!

    var body: some View {
        Form {
            Section(header: Text("Input")) {
                TextEditor(text: $input)
                    .frame(minHeight: 140)
            }
            Section(header: Text("Settings")) {
                Picker("Mode", selection: $mode) {
                    Text("Enhance").tag(Mode.enhance)
                    Text("Reply").tag(Mode.reply)
                }
                Picker("Style", selection: $style) {
                    ForEach(Style.allCases, id: \.self) { s in
                        Text(s.rawValue.capitalized).tag(s)
                    }
                }
            }
            Section {
                Button(action: runTest) {
                    HStack {
                        if isGenerating { ProgressView().progressViewStyle(.circular) }
                        Text(isGenerating ? "Generating…" : "Run Test")
                    }
                }
                .disabled(isGenerating || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section(header: Text("Output")) {
                if output.isEmpty {
                    Text("The result will appear here.")
                        .foregroundColor(.secondary)
                } else {
                    Text(output)
                        .textSelection(.enabled)
                }
            }
            Section(footer: Text("Tip: Ensure you've opened the app at least once so the bundled GGUF is installed into the shared container for the keyboard.").font(.footnote)) { EmptyView() }
        }
        .navigationTitle("Quick Test")
    }

    private func runTest() {
        isGenerating = true
        output = ""
        let useLocal = (defaults.object(forKey: USE_LOCAL_MODEL_KEY) as? Bool) ?? true
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if useLocal {
            let prompt = PromptBuilder.prompt(text: text, mode: mode, style: style)
            local.generate(prompt: prompt, maxTokens: (mode == .reply ? 160 : 100), temp: 0.6, topK: 40, topP: 0.9) { res in
                DispatchQueue.main.async {
                    isGenerating = false
                    switch res {
                    case .success(let s): output = s
                    case .failure(let e): output = "Local error: \(e.localizedDescription)"
                    }
                }
            }
        } else {
            bridge.transform(text: text, mode: mode, style: style) { res in
                DispatchQueue.main.async {
                    isGenerating = false
                    switch res {
                    case .success(let s): output = s
                    case .failure(let e): output = "Server error: \(e.localizedDescription)"
                    }
                }
            }
        }
    }
}
