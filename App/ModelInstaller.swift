import Foundation

struct ModelInstaller {
    static func installIfNeeded() throws -> URL {
        let fm = FileManager.default
        let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: APP_GROUP_ID)!
        // If a model already exists in the app group, use it
        if let existing = try? fm.contentsOfDirectory(at: groupURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .first(where: { $0.pathExtension.lowercased() == "gguf" }) {
            return existing
        }
        // Find any .gguf file in the bundled resources (search recursively)
        var src: URL? = nil
        if let resourcePath = Bundle.main.resourcePath {
            let resourceURL = URL(fileURLWithPath: resourcePath)
            if let e = fm.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
                for case let url as URL in e {
                    if url.pathExtension.lowercased() == "gguf" { src = url; break }
                }
            }
        }
        guard let source = src else {
            throw NSError(domain: "Model", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not bundled"])
        }
        let dst = groupURL.appendingPathComponent(source.lastPathComponent)
        try? fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: groupURL.path)
        if !fm.fileExists(atPath: dst.path) {
            try fm.copyItem(at: source, to: dst)
        }
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var noBackup = dst; try? noBackup.setResourceValues(values)
        return dst
    }
}
