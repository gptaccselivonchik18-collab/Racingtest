#include "CoachLlama.h"
#if __has_include(<llama/llama.h>)
#include <llama/llama.h>
#else
#include <llama.h>
#endif
#include <string>
#include <vector>
#include <cstring>
#include <chrono>
#include <mutex>

int coach_llama_generate(const char *path, const char *system, const char *prompt, char *output, int capacity, coach_cancel_fn cancelled, void *user) {
    static std::once_flag initialized;
    std::call_once(initialized, [] { llama_backend_init(); });
    if (cancelled(user)) return -2;
    auto mp = llama_model_default_params(); mp.n_gpu_layers = 0;
    llama_model *model = llama_model_load_from_file(path, mp);
    if (!model) return -3;
    auto cp = llama_context_default_params(); cp.n_ctx = 2048; cp.n_batch = 256; cp.n_threads = 2; cp.n_threads_batch = 2;
    cp.abort_callback = cancelled; cp.abort_callback_data = user;
    llama_context *ctx = llama_init_from_model(model, cp);
    if (!ctx) { llama_model_free(model); return -4; }
    auto sampler = llama_sampler_init_greedy();
    auto finish = [&](int result) { llama_sampler_free(sampler); llama_free(ctx); llama_model_free(model); return result; };
    const auto *vocab = llama_model_get_vocab(model);
    llama_chat_message messages[] = {{"system",system},{"user",prompt}};
    const char *tmpl = llama_model_chat_template(model, nullptr);
    int length = llama_chat_apply_template(tmpl, messages, 2, true, nullptr, 0);
    if (length <= 0 || length > 40000) return finish(-5);
    std::vector<char> formatted(length + 1);
    llama_chat_apply_template(tmpl, messages, 2, true, formatted.data(), (int)formatted.size());
    int count = -llama_tokenize(vocab, formatted.data(), length, nullptr, 0, true, true);
    if (count <= 0 || count > 1500) return finish(-6);
    std::vector<llama_token> tokens(count);
    count = llama_tokenize(vocab, formatted.data(), length, tokens.data(), count, true, true);
    if (count <= 0) return finish(-6);
    auto started = std::chrono::steady_clock::now();
    auto abort = [&] { return cancelled(user) || std::chrono::steady_clock::now() - started > std::chrono::seconds(45); };
    for (int offset=0; offset<count; offset+=256) {
        if (abort()) return finish(-2);
        auto batch = llama_batch_get_one(tokens.data()+offset, std::min(256,count-offset));
        if (llama_decode(ctx,batch)) return finish(-7);
    }
    std::string result;
    for (int i=0; i<400; ++i) {
        if (abort()) return finish(-2);
        llama_token token = llama_sampler_sample(sampler,ctx,-1);
        if (llama_vocab_is_eog(vocab,token)) break;
        char piece[512]; int n = llama_token_to_piece(vocab,token,piece,sizeof(piece),0,false);
        if (n < 0) return finish(-8);
        if ((int)result.size()+n >= capacity) break;
        result.append(piece,n);
        auto batch = llama_batch_get_one(&token,1);
        if (llama_decode(ctx,batch)) return finish(-7);
    }
    memcpy(output,result.data(),result.size()); output[result.size()]=0;
    return finish((int)result.size());
}
