import Foundation

final class LocalLLM {
    private var initialized = false
    private var lastInitError: String?
    private let queue = DispatchQueue(label: "kb.llm.queue", qos: .userInitiated)

    func initializeIfNeeded() {
        guard !initialized else { return }
        let fm = FileManager.default
        let groupURLOpt = fm.containerURL(forSecurityApplicationGroupIdentifier: APP_GROUP_ID)

        if groupURLOpt == nil {
            print("[LocalLLM] WARN: App Group container unavailable for \(APP_GROUP_ID). Will use bundle model directly if present.")
        }
        // Debug: list App Group contents
        print("[LocalLLM] DEBUG: App Group path: \(groupURLOpt?.path ?? "(nil)")")
        let groupContents: [URL] = {
            guard let u = groupURLOpt else { return [] }
            return (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        }()
        print("[LocalLLM] DEBUG: App Group contents: \(groupContents.map { $0.lastPathComponent })")

        // 1) Prefer an existing .gguf model in the App Group container
        var modelURL: URL? = groupContents.first(where: { $0.pathExtension.lowercased() == "gguf" })

        // 2) If absent, search for any GGUF in our own bundle resources
        if modelURL == nil {
            print("[LocalLLM] DEBUG: No model in App Group, searching bundle resources…")

            // Try explicit file name first (model.gguf)
            if let modelsPath = Bundle.main.path(forResource: "model", ofType: "gguf") {
                let url = URL(fileURLWithPath: modelsPath)
                print("[LocalLLM] DEBUG: Found model.gguf at: \(modelsPath)")
                if let groupURL = groupURLOpt {
                    let dst = groupURL.appendingPathComponent("model.gguf")
                    do {
                        if !fm.fileExists(atPath: dst.path) {
                            print("[LocalLLM] DEBUG: Copying model.gguf to App Group…")
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
                    modelURL = url // No App Group; use bundle
                }
            } else {
                // Fallback: search recursively in extension bundle
                if let resourcePath = Bundle.main.resourcePath {
                    print("[LocalLLM] DEBUG: model.gguf not found, searching recursively in: \(resourcePath)")
                    let resourceURL = URL(fileURLWithPath: resourcePath)
                    if let e = fm.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
                        for case let url as URL in e where url.pathExtension.lowercased() == "gguf" {
                            print("[LocalLLM] DEBUG: Found GGUF file: \(url.path)")
                            if let groupURL = groupURLOpt {
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
                            } else {
                                modelURL = url
                            }
                            break
                        }
                    }
                }

                // As a last resort, attempt to locate main app bundle and search there (when both targets embed resources)
                if modelURL == nil {
                    print("[LocalLLM] DEBUG: No model found in extension bundle, searching main app bundle…")
                    if let extensionPath = Bundle.main.bundleURL as URL? {
                        // Keyboard.appex is inside KeyboardAI.app/PlugIns/Keyboard.appex
                        // Go up two levels to reach KeyboardAI.app
                        let mainAppURL = extensionPath.deletingLastPathComponent().deletingLastPathComponent()
                        print("[LocalLLM] DEBUG: Main app candidate: \(mainAppURL.path)")
                        if let e = fm.enumerator(at: mainAppURL, includingPropertiesForKeys: nil) {
                            for case let url as URL in e where url.pathExtension.lowercased() == "gguf" {
                                print("[LocalLLM] DEBUG: Found GGUF file in main app: \(url.path)")
                                if let groupURL = groupURLOpt {
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
                                } else {
                                    modelURL = url
                                }
                                break
                            }
                        }
                    }
                }
            }
        }

        guard let url = modelURL else {
            lastInitError = "No .gguf model found in App Group container or bundle. App Group: \(groupURLOpt?.path ?? "(nil)")"
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
