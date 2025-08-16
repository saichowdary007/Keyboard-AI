#include "llama_wrapper.h"

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <cstdio>

#if __has_include("llama.h")
// Real implementation using llama.cpp
#include "llama.h"

static struct llama_model *g_model = nullptr;
static struct llama_context *g_ctx  = nullptr;

extern "C" int kb_llm_init(const char *model_path, int n_ctx, int n_threads) {
    if (g_ctx) return 1; // already loaded

    std::fprintf(stderr, "[llama_wrapper] Using REAL llama.cpp. model='%s' n_ctx=%d n_threads=%d\n", model_path ? model_path : "(null)", n_ctx, n_threads);
    llama_backend_init();

    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 999; // offload to Metal where possible
    g_model = llama_model_load_from_file(model_path, mparams);
    if (!g_model) {
        std::fprintf(stderr, "[llama_wrapper] ERROR: llama_model_load_from_file failed for '%s'\n", model_path ? model_path : "(null)");
        return 0;
    }

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = n_ctx;
    cparams.n_threads = n_threads;
    cparams.n_threads_batch = n_threads;
    g_ctx = llama_init_from_model(g_model, cparams);
    if (!g_ctx) {
        std::fprintf(stderr, "[llama_wrapper] ERROR: llama_init_from_model failed\n");
        return 0;
    }
    return 1;
}

extern "C" int kb_llm_unload(void) {
    if (g_ctx) { llama_free(g_ctx); g_ctx = nullptr; }
    if (g_model) { llama_model_free(g_model); g_model = nullptr; }
    llama_backend_free();
    return 1;
}

extern "C" int kb_llm_generate(const char *prompt,
                                int max_tokens,
                                float temp,
                                int top_k,
                                float top_p,
                                const char **out_text) {
    if (!g_ctx || !g_model) {
        std::fprintf(stderr, "[llama_wrapper] ERROR: kb_llm_generate called without initialized context/model\n");
        return 0;
    }

    // acquire vocab
    const struct llama_vocab * vocab = llama_model_get_vocab(g_model);
    if (!vocab) return 0;

    // build sampler chain according to params
    auto chain_params = llama_sampler_chain_default_params();
    chain_params.no_perf = true;
    struct llama_sampler * smpl = llama_sampler_chain_init(chain_params);
    if (top_k > 0)          { llama_sampler_chain_add(smpl, llama_sampler_init_top_k(top_k)); }
    if (top_p < 1.0f)       { llama_sampler_chain_add(smpl, llama_sampler_init_top_p(top_p, 1)); }
    if (temp > 0.0f && temp != 1.0f) { llama_sampler_chain_add(smpl, llama_sampler_init_temp(temp)); }
    // final sampler: greedy for deterministic, otherwise RNG-based
    if (temp <= 0.0f) {
        llama_sampler_chain_add(smpl, llama_sampler_init_greedy());
    } else {
        llama_sampler_chain_add(smpl, llama_sampler_init_dist((uint32_t) llama_time_us()));
    }

    // tokenize prompt
    const int32_t text_len = (int32_t) std::strlen(prompt);
    int32_t n_prompt = -llama_tokenize(vocab, prompt, text_len, nullptr, 0, true, true);
    if (n_prompt <= 0) { llama_sampler_free(smpl); return 0; }
    std::vector<llama_token> tokens(n_prompt);
    if (llama_tokenize(vocab, prompt, text_len, tokens.data(), n_prompt, true, true) < 0) {
        llama_sampler_free(smpl);
        return 0;
    }

    // evaluate prompt
    llama_batch batch = llama_batch_get_one(tokens.data(), (int32_t) tokens.size());
    if (llama_decode(g_ctx, batch) != 0) {
        llama_sampler_free(smpl);
        std::fprintf(stderr, "[llama_wrapper] ERROR: llama_decode failed for prompt\n");
        return 0;
    }

    std::string out;
    for (int i = 0; i < max_tokens; ++i) {
        const llama_token id = llama_sampler_sample(smpl, g_ctx, -1);
        if (llama_vocab_is_eog(vocab, id)) break;

        char buf[128];
        const int n = llama_token_to_piece(vocab, id, buf, (int32_t) sizeof(buf), 0, true);
        if (n > 0) out.append(buf, n);

        // feed the sampled token back
        llama_token t = id;
        batch = llama_batch_get_one(&t, 1);
        if (llama_decode(g_ctx, batch) != 0) {
            std::fprintf(stderr, "[llama_wrapper] ERROR: llama_decode failed during generation\n");
            break;
        }
        llama_sampler_accept(smpl, id);
    }

    llama_sampler_free(smpl);

    char *mem = (char*) std::malloc(out.size() + 1);
    if (!mem) return 0;
    std::memcpy(mem, out.c_str(), out.size() + 1);
    *out_text = mem;
    return 1;
}

#else
// Stubbed implementation when llama.cpp is not present
extern "C" int kb_llm_init(const char * /*model_path*/, int /*n_ctx*/, int /*n_threads*/) { return 0; }
extern "C" int kb_llm_unload(void) { return 1; }
extern "C" int kb_llm_generate(const char * /*prompt*/, int /*max_tokens*/, float /*temp*/, int /*top_k*/, float /*top_p*/, const char **out_text) {
    *out_text = nullptr;
    return 0;
}
#endif
