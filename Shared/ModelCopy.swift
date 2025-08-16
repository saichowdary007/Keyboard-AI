import Foundation

@discardableResult
public func copyGGUFModelToAppGroupIfNeeded(modelFileName: String = "gemma-3-270m-it.gguf") -> URL? {
    let fm = FileManager.default
    guard let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: APP_GROUP_ID) else {
        print("❌ App Group unavailable for \(APP_GROUP_ID)")
        return nil
    }

    // If a model already exists in the app group, return it
    if let existing = try? fm.contentsOfDirectory(at: groupURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        .first(where: { $0.pathExtension.lowercased() == "gguf" }) {
        return existing
    }

    // Find the model in this target's bundle (search recursively)
    if let resourcePath = Bundle.main.resourcePath {
        let resourceURL = URL(fileURLWithPath: resourcePath)
        if let e = fm.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let url as URL in e {
                if url.lastPathComponent == modelFileName || url.pathExtension.lowercased() == "gguf" {
                    let dst = groupURL.appendingPathComponent(url.lastPathComponent)
                    do {
                        if !fm.fileExists(atPath: dst.path) {
                            try fm.copyItem(at: url, to: dst)
                        }
                        var values = URLResourceValues(); values.isExcludedFromBackup = true
                        var noBackup = dst; try? noBackup.setResourceValues(values)
                        print("✅ Model copied to App Group: \(dst.path)")
                        return dst
                    } catch {
                        print("❌ Copy failed: \(error.localizedDescription)")
                        // Fallback: allow direct use of bundled model if needed
                        return url
                    }
                }
            }
        }
    }

    print("❌ Model not found in bundle")
    return nil
}
