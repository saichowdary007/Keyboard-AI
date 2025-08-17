import Foundation

struct ModelInstaller {
    /// Returns the App Group container URL or throws if unavailable
    static func appGroupURL() throws -> URL {
        let fm = FileManager.default
        if let u = fm.containerURL(forSecurityApplicationGroupIdentifier: APP_GROUP_ID) { return u }
        throw NSError(domain: "Model", code: -10, userInfo: [NSLocalizedDescriptionKey: "App Group container unavailable for \(APP_GROUP_ID)"])
    }

    /// Returns the currently installed model URL in the App Group, if any
    static func installedModelURL() -> URL? {
        let fm = FileManager.default
        guard let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: APP_GROUP_ID) else { return nil }
        return try? fm.contentsOfDirectory(at: groupURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .first(where: { $0.pathExtension.lowercased() == "gguf" })
    }

    /// Finds any .gguf file in the app bundle (recursive search)
    static func bundledModelURL() -> URL? {
        let fm = FileManager.default
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let resourceURL = URL(fileURLWithPath: resourcePath)
        if let e = fm.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let url as URL in e { if url.pathExtension.lowercased() == "gguf" { return url } }
        }
        return nil
    }

    /// Human-readable size of a file at URL
    static func fileSizeString(_ url: URL) -> String {
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: url.path), let bytes = attrs[.size] as? NSNumber {
            let mb = Double(truncating: bytes) / (1024.0 * 1024.0)
            return String(format: "%.1f MB", mb)
        }
        return "-"
    }

    static func installIfNeeded() throws -> URL {
        let fm = FileManager.default
        let groupURL = try appGroupURL()

        print("[ModelInstaller] App Group: \(groupURL.path)")
        let existing = installedModelURL()
        if let m = existing {
            print("[ModelInstaller] Model already installed: \(m.lastPathComponent) (\(fileSizeString(m)))")
            return m
        }

        guard let source = bundledModelURL() else {
            print("[ModelInstaller] ERROR: No .gguf found in app bundle")
            throw NSError(domain: "Model", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not bundled in app"])
        }

        let dst = groupURL.appendingPathComponent(source.lastPathComponent)
        print("[ModelInstaller] Installing bundled model -> App Group")
        print("[ModelInstaller] Source: \(source.path)")
        print("[ModelInstaller] Dest:   \(dst.path)")

        try? fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: groupURL.path)
        if !fm.fileExists(atPath: dst.path) {
            try fm.copyItem(at: source, to: dst)
        }
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var noBackup = dst; try? noBackup.setResourceValues(values)
        print("[ModelInstaller] Installed: \(dst.lastPathComponent) (\(fileSizeString(dst)))")
        return dst
    }

    /// Remove any installed .gguf from the App Group to allow clean reinstall
    static func resetInstalledModel() throws {
        let fm = FileManager.default
        let groupURL = try appGroupURL()
        let items = try fm.contentsOfDirectory(at: groupURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        for url in items where url.pathExtension.lowercased() == "gguf" {
            try? fm.removeItem(at: url)
        }
        print("[ModelInstaller] Reset: removed installed GGUF(s) from App Group")
    }
}