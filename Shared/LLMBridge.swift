import Foundation

public struct LLMRequest: Codable { let text: String; let mode: Mode; let style: Style }

public final class LLMBridge {
    private let defaults = UserDefaults(suiteName: APP_GROUP_ID)!

    public init() {}

    public func transform(text: String, mode: Mode, style: Style,
                          completion: @escaping (Result<String, Error>) -> Void) {
        guard var endpoint = defaults.string(forKey: DEFAULT_API_ENDPOINT_KEY)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !endpoint.isEmpty else {
            completion(.failure(TransformError.badResponse)); return
        }
        // Normalize endpoint: if missing scheme, default to https
        var maybeURL = URL(string: endpoint)
        if maybeURL?.scheme == nil {
            maybeURL = URL(string: "https://" + endpoint)
        }
        guard let url = maybeURL,
              let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https"),
              let host = url.host, !host.isEmpty else {
            completion(.failure(TransformError.badResponse)); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = defaults.string(forKey: DEFAULT_API_KEY_KEY), !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let payload = LLMRequest(text: text, mode: mode, style: style)
        req.httpBody = try? JSONEncoder().encode(payload)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let out = obj["text"] as? String else {
                completion(.failure(TransformError.badResponse)); return
            }
            completion(.success(out))
        }.resume()
    }
}
