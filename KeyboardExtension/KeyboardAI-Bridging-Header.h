// KeyboardAI-Bridging-Header.h
// Expose llama.cpp wrapper C API to Swift

#ifdef __cplusplus
extern "C" {
#endif

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
