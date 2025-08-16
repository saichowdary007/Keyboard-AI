import SwiftUI

@main
struct KeyboardAIApp: App {
    init() {
        // Ensure the model is present in the App Group container ASAP on app launch
        print("[ModelCopy] Ensuring model in App Group at app init")
        _ = copyGGUFModelToAppGroupIfNeeded()
    }
    var body: some Scene {
        WindowGroup {
            SettingsView()
        }
    }
}
