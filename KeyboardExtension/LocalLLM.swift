import Foundation

final class LocalLLM {
    private var initialized = false
    private var lastInitError: String?
    private let queue = DispatchQueue(label: "kb.llm.queue", qos: .userInitiated)

    func initializeIfNeeded() {
        guard !initialized else { return }
        let fm = FileManager.default
        guard let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: APP_GROUP_ID) else {
            lastInitError = "App Group container unavailable for \(APP_GROUP_ID)"
            print("[LocalLLM] ERROR: \(lastInitError!)")
            return
        }
        // Find any .gguf model in the app group container; if missing, try to copy from the extension bundle
        var modelURL: URL? = (try? fm.contentsOfDirectory(at: groupURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?
            .first(where: { $0.pathExtension.lowercased() == "gguf" })
        if modelURL == nil {
            // Attempt to locate a bundled .gguf within the extension's resources and copy it to the App Group container
            if let resourcePath = Bundle.main.resourcePath {
                let resourceURL = URL(fileURLWithPath: resourcePath)
                if let e = fm.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
                    for case let url as URL in e {
                        if url.pathExtension.lowercased() == "gguf" {
                            let dst = groupURL.appendingPathComponent(url.lastPathComponent)
                            do {
                                if !fm.fileExists(atPath: dst.path) {
                                    try fm.copyItem(at: url, to: dst)
                                }
                                var values = URLResourceValues(); values.isExcludedFromBackup = true
                                var noBackup = dst; try? noBackup.setResourceValues(values)
                                modelURL = dst
                                print("[LocalLLM] Installed bundled model into App Group: \(dst.lastPathComponent)")
                            } catch {
                                // If copy fails (e.g., permission), try using the bundled model directly as a fallback
                                print("[LocalLLM] ERROR: Failed to copy bundled model to App Group: \(error.localizedDescription)")
                                modelURL = url
                                print("[LocalLLM] Falling back to using bundled model directly: \(url.lastPathComponent)")
                            }
                            break
                        }
                    }
                }
            }
        }
        guard let url = modelURL else {
            lastInitError = "No .gguf model found in App Group container: \(groupURL.path)"
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
