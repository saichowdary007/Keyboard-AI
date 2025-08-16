import UIKit
import UniformTypeIdentifiers

final class ReplyActionViewController: UIViewController {
    private let local = LocalLLM()
    private let defaults = UserDefaults(suiteName: APP_GROUP_ID)!
    private var style: Style = .formal

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        extractText { [weak self] text in
            guard let self = self else { return }
            guard let text = text, !text.isEmpty else { self.finish("No text"); return }
            let prompt = PromptBuilder.prompt(text: text, mode: .reply, style: self.style)
            self.local.generate(prompt: prompt, maxTokens: 160, temp: 0.6, topK: 40, topP: 0.9) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let reply):
                        UIPasteboard.general.string = reply
                        self.defaults.set(reply, forKey: "lastGeneratedReply")
                        self.finish("Reply copied")
                    case .failure(let e):
                        self.finish("Error: \(e.localizedDescription)")
                    }
                }
            }
        }
    }

    private func extractText(completion: @escaping (String?) -> Void) {
        guard let item = self.extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments else { completion(nil); return }
        let type = UTType.plainText.identifier
        for provider in providers where provider.hasItemConformingToTypeIdentifier(type) {
            provider.loadItem(forTypeIdentifier: type, options: nil) { (item, error) in
                if let s = item as? String { completion(s); return }
                completion(nil)
            }
            return
        }
        completion(nil)
    }

    private func finish(_ message: String) {
        self.extensionContext?.completeRequest(returningItems: nil)
    }
}
