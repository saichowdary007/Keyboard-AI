import SwiftUI

struct SettingsView: View {
    @State private var endpoint: String = UserDefaults(suiteName: APP_GROUP_ID)?.string(forKey: DEFAULT_API_ENDPOINT_KEY) ?? ""
    @State private var apiKey: String = UserDefaults(suiteName: APP_GROUP_ID)?.string(forKey: DEFAULT_API_KEY_KEY) ?? ""
    // Default to true when the key is not yet set in shared defaults
    @State private var useLocal: Bool = (UserDefaults(suiteName: APP_GROUP_ID)?.object(forKey: USE_LOCAL_MODEL_KEY) as? Bool) ?? true
    @State private var installing: Bool = false
    @State private var installStatus: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Offline (Recommended)")) {
                    Toggle("Use local model (offline)", isOn: $useLocal)
                        .onChange(of: useLocal) { _ in save() }
                    HStack(spacing: 8) {
                        Image(systemName: statusIconName())
                            .foregroundColor(statusIconColor())
                        Text(installStatus.isEmpty ? "Checking…" : installStatus)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Button(installing ? "Installing…" : "Install/Repair Local Model") { installOrRepair() }
                            .disabled(installing)
                        Spacer()
                        Button("Reset Installed Model", role: .destructive) { resetModel() }
                    }
                }

                Section(header: Text("Server (Fallback for future)"), footer: Text("You can leave these empty to stay fully offline. When enabled in a future update, the keyboard can fall back to your server if the local model is unavailable.").font(.footnote)) {
                    TextField("API Endpoint (https://example.com/api)", text: $endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)
                    SecureField("API Key (optional)", text: $apiKey)
                    Button("Save Server Settings") { save() }
                }

                Section(header: Text("Diagnostics")) {
                    NavigationLink(destination: QuickTestView()) { Text("Quick Test") }
                }

                Section(header: Text("Privacy")) {
                    Text("Full Access is required for online rewriting. We never log keystrokes.")
                }
            }
            .navigationTitle("KeyboardAI Settings")
            .onAppear { refreshStatus() }
        }
    }

    private func statusIconName() -> String {
        if installStatus.hasPrefix("Installed:") { return "checkmark.seal.fill" }
        if installStatus.hasPrefix("Bundled:") { return "tray.and.arrow.down.fill" }
        return "exclamationmark.triangle.fill"
    }

    private func statusIconColor() -> Color {
        if installStatus.hasPrefix("Installed:") { return .green }
        if installStatus.hasPrefix("Bundled:") { return .blue }
        return .orange
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

    private func installOrRepair() {
        installing = true
        DispatchQueue.global(qos: .userInitiated).async {
            do { _ = try ModelInstaller.installIfNeeded() } catch {
                print("[ModelInstaller] UI install error: \(error)")
            }
            DispatchQueue.main.async {
                installing = false
                refreshStatus()
            }
        }
    }

    private func resetModel() {
        installing = true
        DispatchQueue.global(qos: .userInitiated).async {
            do { try ModelInstaller.resetInstalledModel() } catch {
                print("[ModelInstaller] Reset error: \(error)")
            }
            DispatchQueue.main.async {
                installing = false
                refreshStatus()
            }
        }
    }

    private func refreshStatus() {
        if let u = ModelInstaller.installedModelURL() {
            installStatus = "Installed: \(u.lastPathComponent) (\(ModelInstaller.fileSizeString(u)))"
        } else if let b = ModelInstaller.bundledModelURL() {
            installStatus = "Bundled: \(b.lastPathComponent) — tap Install to copy to App Group"
        } else {
            installStatus = "No model bundled in app"
        }
    }
}