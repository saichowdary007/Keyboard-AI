import Foundation

final class LocalLLM {
    private var initialized = false
    private var lastInitError: String?
    private let queue = DispatchQueue(label: "kb.llm.queue", qos: .userInitiated)

    func initializeIfNeeded() {
        guard !initialized else { return }
        let fm = FileManager.default
        let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: APP_GROUP_ID)
        
        if groupURL == nil {
            print("[LocalLLM] ERROR: App Group container unavailable for \(APP_GROUP_ID)")
            print("[LocalLLM] Will search for model in bundle resources only")
        }
        // Debug: list App Group contents
        print("[LocalLLM] DEBUG: App Group path: \(groupURL.path)")
        let groupContents = (try? fm.contentsOfDirectory(at: groupURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        print("[LocalLLM] DEBUG: App Group contents: \(groupContents.map { $0.lastPathComponent })")

        // 1) Check for an existing .gguf model in the App Group container
        var modelURL: URL? = groupContents.first(where: { $0.pathExtension.lowercased() == "gguf" })

        // 2) If absent, search bundle explicitly for model.gguf, then fallback to recursive search
        if modelURL == nil {
            print("[LocalLLM] DEBUG: No model in App Group, searching bundle resources...")

            // Try explicit file name first
            if let modelsPath = Bundle.main.path(forResource: "model", ofType: "gguf") {
                let url = URL(fileURLWithPath: modelsPath)
                print("[LocalLLM] DEBUG: Found model.gguf at: \(modelsPath)")
                let dst = groupURL.appendingPathComponent("model.gguf")
                do {
                    if !fm.fileExists(atPath: dst.path) {
                        print("[LocalLLM] DEBUG: Copying model.gguf to App Group...")
                        try fm.copyItem(at: url, to: dst)
                    }
                    var values = URLResourceValues(); values.isExcludedFromBackup = true
                    var noBackup = dst; try? noBackup.setResourceValues(values)
                    modelURL = dst
                    print("[LocalLLM] Successfully installed model.gguf into App Group")
                } catch {
                    print("[LocalLLM] ERROR: Failed to copy model.gguf to App Group: \(error)")
                    modelURL = url // Use directly from bundle as fallback
                    print("[LocalLLM] Using model.gguf directly from bundle")
                }
            } else {
                // Fallback: search recursively in keyboard extension bundle first
                if let resourcePath = Bundle.main.resourcePath {
                    print("[LocalLLM] DEBUG: model.gguf not found, searching recursively in: \(resourcePath)")
                    let resourceURL = URL(fileURLWithPath: resourcePath)
                    if let e = fm.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
                        for case let url as URL in e {
                            if url.pathExtension.lowercased() == "gguf" {
                                print("[LocalLLM] DEBUG: Found GGUF file: \(url.path)")
                                let dst = groupURL.appendingPathComponent(url.lastPathComponent)
                                do {
                                    if !fm.fileExists(atPath: dst.path) {
                                        try fm.copyItem(at: url, to: dst)
                                    }
                                    var values = URLResourceValues(); values.isExcludedFromBackup = true
                                    var noBackup = dst; try? noBackup.setResourceValues(values)
                                    modelURL = dst
                                    print("[LocalLLM] Successfully installed \(url.lastPathComponent) into App Group")
                                } catch {
                                    print("[LocalLLM] ERROR: Failed to copy to App Group: \(error)")
                                    modelURL = url
                                    print("[LocalLLM] Using model directly from bundle: \(url.lastPathComponent)")
                                }
                                break
                            }
                        }
                    }
                }
                
                // If still not found, try to find the main app bundle and search there
                if modelURL == nil {
                    print("[LocalLLM] DEBUG: No model found in keyboard extension bundle, searching main app bundle...")
                    // The main app bundle should be at ../../KeyboardAI.app relative to the keyboard extension
                    if let extensionPath = Bundle.main.bundlePath as NSString? {
                        let mainAppPath = extensionPath.deletingLastPathComponent.appending("/KeyboardAI.app")
                        let mainAppURL = URL(fileURLWithPath: mainAppPath)
                        print("[LocalLLM] DEBUG: Searching main app bundle at: \(mainAppPath)")
                        
                        if let e = fm.enumerator(at: mainAppURL, includingPropertiesForKeys: nil) {
                            for case let url as URL in e {
                                if url.pathExtension.lowercased() == "gguf" {
                                    print("[LocalLLM] DEBUG: Found GGUF file in main app: \(url.path)")
                                    let dst = groupURL.appendingPathComponent(url.lastPathComponent)
                                    do {
                                        if !fm.fileExists(atPath: dst.path) {
                                            try fm.copyItem(at: url, to: dst)
                                        }
                                        var values = URLResourceValues(); values.isExcludedFromBackup = true
                                        var noBackup = dst; try? noBackup.setResourceValues(values)
                                        modelURL = dst
                                        print("[LocalLLM] Successfully installed \(url.lastPathComponent) from main app into App Group")
                                    } catch {
                                        print("[LocalLLM] ERROR: Failed to copy from main app to App Group: \(error)")
                                        modelURL = url
                                        print("[LocalLLM] Using model directly from main app bundle: \(url.lastPathComponent)")
                                    }
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }
        guard let url = modelURL else {
            lastInitError = "No .gguf model found in App Group container or bundle. App Group: \(groupURL.path)"
            print("[LocalLLM] ERROR: \(lastInitError!)")
            return
        }
        print("[LocalLLM] Found model at: \(url.path)")
        let nctx = 512
        let nthreads = max(2, ProcessInfo.processInfo.processorCount - 2)
        print("[LocalLLM] Initializing model with n_ctx=\(nctx), n_threads=\(nthreads)")
        url.path.withCString { cpath in
            let ok = kb_llm_init(cpath, Int32(nctx), Int32(nthreads))
            initialized = (ok != 0)
            if !initialized {
                lastInitError = "kb_llm_init failed for \(url.lastPathComponent)"
                print("[LocalLLM] ERROR: \(lastInitError!)")
            } else {
                print("[LocalLLM] Initialization succeeded")
            }
        }
    }

    func generate(prompt: String, maxTokens: Int = 120, temp: Float = 0.7, topK: Int = 30, topP: Float = 0.95, completion: @escaping (Result<String, Error>) -> Void) {
        initializeIfNeeded()
        guard initialized else {
            let msg = lastInitError ?? "Local model unavailable"
            completion(.failure(NSError(domain: "LLM", code: 1001, userInfo: [NSLocalizedDescriptionKey: msg])))
            return
        }
        queue.async {
            var cOut: UnsafePointer<CChar>? = nil
            prompt.withCString { cstr in
                let ok = kb_llm_generate(cstr, Int32(maxTokens), temp, Int32(topK), topP, &cOut)
                if ok == 0 {
                    completion(.failure(NSError(domain: "LLM", code: 2, userInfo: [NSLocalizedDescriptionKey: "gen failed"]))); return
                }
            }
            if let cstr = cOut {
                let s = String(cString: cstr)
                free(UnsafeMutableRawPointer(mutating: cstr))
                completion(.success(s))
            } else {
                completion(.failure(NSError(domain: "LLM", code: 3, userInfo: [NSLocalizedDescriptionKey: "nil out"])))
            }
        }
    }

    func unload() { _ = kb_llm_unload(); initialized = false }
}
