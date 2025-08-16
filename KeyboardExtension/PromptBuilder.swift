import Foundation

enum PromptBuilder {
    static func prompt(text: String, mode: Mode, style: Style) -> String {
        switch mode {
        case .enhance:
            return (
                "You are a concise editor. Improve clarity and tone to {STYLE}. Keep meaning. Keep similar length. Output only the revised text. " +
                "TEXT: <<<\(text)>>> {STYLE}: \(style.rawValue)"
            )
        case .reply:
            return (
                "You write short {STYLE} replies. Read the message and produce a direct reply in 1-4 sentences. No greetings if it’s chat. " +
                "MESSAGE: <<<\(text)>>> {STYLE}: \(style.rawValue)"
            )
        }
    }
}
