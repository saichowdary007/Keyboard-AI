import SwiftUI

struct SettingsView: View {
    @State private var endpoint: String = UserDefaults(suiteName: APP_GROUP_ID)?.string(forKey: DEFAULT_API_ENDPOINT_KEY) ?? ""
    @State private var apiKey: String = UserDefaults(suiteName: APP_GROUP_ID)?.string(forKey: DEFAULT_API_KEY_KEY) ?? ""
    // Default to true when the key is not yet set in shared defaults
    @State private var useLocal: Bool = (UserDefaults(suiteName: APP_GROUP_ID)?.object(forKey: USE_LOCAL_MODEL_KEY) as? Bool) ?? true

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server")) {
                    TextField("API Endpoint", text: $endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    SecureField("API Key (optional)", text: $apiKey)
                    Button("Save") { save() }
                }
                Section(header: Text("Offline")) {
                    Toggle("Use local model (offline)", isOn: $useLocal)
                        .onChange(of: useLocal) { _ in save() }
                    Text("Place your GGUF model in the app bundle to enable offline mode.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Section(header: Text("Privacy")) {
                    Text("Full Access is required for online rewriting. We never log keystrokes.")
                }
            }
            .navigationTitle("KeyboardAI Settings")
        }
    }

    private func save() {
        let d = UserDefaults(suiteName: APP_GROUP_ID)!
        // Normalize endpoint: trim, prepend https:// if missing scheme, or clear if empty
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            d.removeObject(forKey: DEFAULT_API_ENDPOINT_KEY)
        } else if trimmed.contains("://") {
            d.set(trimmed, forKey: DEFAULT_API_ENDPOINT_KEY)
        } else {
            d.set("https://\(trimmed)", forKey: DEFAULT_API_ENDPOINT_KEY)
        }
        d.set(apiKey, forKey: DEFAULT_API_KEY_KEY)
        d.set(useLocal, forKey: USE_LOCAL_MODEL_KEY)
    }
}
