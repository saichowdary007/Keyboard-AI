import SwiftUI

@main
struct KeyboardAIApp: App {
    init() {
        // Ensure the model is installed into the App Group container ASAP on app launch
        print("[ModelInstaller] Running installIfNeeded() at app init")
        _ = try? ModelInstaller.installIfNeeded()
    }
    var body: some Scene {
        WindowGroup {
            SettingsView()
        }
    }
}
