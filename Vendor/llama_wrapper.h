#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Minimal C API exposed to Swift via bridging header
int kb_llm_init(const char *model_path, int n_ctx, int n_threads);
int kb_llm_unload(void);
int kb_llm_generate(const char *prompt,
                    int max_tokens,
                    float temp,
                    int top_k,
                    float top_p,
                    const char **out_text /* malloc'd */);

#ifdef __cplusplus
}
#endif
