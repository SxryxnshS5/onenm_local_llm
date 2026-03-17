// Copyright 2026 1nm. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

// =============================================================================
// onenm_bridge.cpp — JNI bridge between Android/Kotlin and llama.cpp
//
// This file implements four JNI functions consumed by OneNmNative.kt:
//
//   initBackend()  – Discovers and registers ggml backends (CPU, etc.)
//                    before model loading. Promotes dependency libs to
//                    RTLD_GLOBAL and falls back to manual registration
//                    when automatic discovery fails.
//   loadModel()    – Loads a GGUF model from disk and creates an inference
//                    context. Initialises the backend if not already done.
//   generate()     – Tokenises a prompt, feeds it through the model, then
//                    samples new tokens using a configurable sampler chain
//                    (repeat-penalty → top-k → top-p → temperature → dist).
//   releaseModel() – Frees the context, model, and backend.
//
// Logging goes to Android logcat under the tags "1nm_bridge" (this file)
// and "llama.cpp" (upstream library).
// =============================================================================

#include <jni.h>
#include <string>
#include <vector>
#include <android/log.h>
#include <dlfcn.h>
#include <dirent.h>
#include <cerrno>

#include "llama.h"
#include "ggml.h"
#include "ggml-backend.h"

#define TAG "1nm_bridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// Redirect llama.cpp internal logs to Android logcat.
static void llama_log_callback(enum ggml_log_level level, const char * text, void * user_data) {
    int prio = ANDROID_LOG_INFO;
    if (level == GGML_LOG_LEVEL_ERROR) prio = ANDROID_LOG_ERROR;
    else if (level == GGML_LOG_LEVEL_WARN) prio = ANDROID_LOG_WARN;
    else if (level == GGML_LOG_LEVEL_DEBUG) prio = ANDROID_LOG_DEBUG;
    __android_log_print(prio, "llama.cpp", "%s", text);
}

// Global model and context — only one model loaded at a time.
static llama_model * model = nullptr;
static llama_context * ctx = nullptr;
static bool backend_initialized = false;

// ---------------------------------------------------------------------------
// initBackend — Discover and load ggml backends before model loading.
//
// Called early (before model download) so backend issues surface immediately.
// Safe to call multiple times — subsequent calls are no-ops.
// ---------------------------------------------------------------------------
extern "C"
JNIEXPORT jboolean JNICALL
Java_com_theorangeshade_onenm_1local_1llm_OneNmNative_initBackend(
        JNIEnv * env,
        jobject thiz,
        jstring nativeLibDir) {

    if (backend_initialized) {
        LOGI("Backend already initialized, skipping");
        return ggml_backend_reg_count() > 0 ? JNI_TRUE : JNI_FALSE;
    }

    const char * lib_dir = env->GetStringUTFChars(nativeLibDir, nullptr);
    LOGI("initBackend: lib dir = %s", lib_dir);

    llama_log_set(llama_log_callback, nullptr);

    // Promote already-loaded dependency libraries to global symbol visibility.
    // System.loadLibrary() in Kotlin loads them with RTLD_LOCAL, so their
    // symbols are not visible when ggml tries to dlopen the CPU backend.
    // RTLD_NOLOAD avoids reloading — it just changes the visibility flag.
    const char * deps[] = {
        "libomp.so",
        "libggml-base.so",
        "libggml.so",
        "libllama.so",
    };
    for (const char * dep : deps) {
        void * h = dlopen(dep, RTLD_NOW | RTLD_NOLOAD | RTLD_GLOBAL);
        if (h) {
            LOGI("Promoted to GLOBAL: %s", dep);
        } else {
            LOGI("Could not promote %s: %s", dep, dlerror() ? dlerror() : "(no error)");
        }
    }

    ggml_backend_load_all_from_path(lib_dir);
    size_t n_backends = ggml_backend_reg_count();
    LOGI("Backends loaded: %zu", n_backends);

    // Fallback: ggml's discovery looks for ggml_backend_reg_init, but some
    // builds export ggml_backend_cpu_reg instead. Manually dlopen + register.
    if (n_backends == 0) {
        std::string cpu_path = std::string(lib_dir) + "/libggml-cpu-android_armv8.2_1.so";
        dlerror(); // clear
        void * handle = dlopen(cpu_path.c_str(), RTLD_NOW | RTLD_GLOBAL);
        if (handle) {
            typedef ggml_backend_reg_t (*reg_fn_t)(void);
            reg_fn_t reg_fn = (reg_fn_t) dlsym(handle, "ggml_backend_cpu_reg");
            if (reg_fn) {
                ggml_backend_reg_t reg = reg_fn();
                if (reg) {
                    ggml_backend_register(reg);
                    n_backends = ggml_backend_reg_count();
                    LOGI("Manually registered CPU backend, backends now: %zu", n_backends);
                }
            } else {
                LOGE("ggml_backend_cpu_reg symbol not found");
            }
        } else {
            const char * err = dlerror();
            LOGE("dlopen failed for CPU backend: %s", err ? err : "(no error)");
        }
    }

    if (n_backends == 0) {
        LOGE("No ggml backends found in: %s", lib_dir);
        DIR * dir = opendir(lib_dir);
        if (dir) {
            LOGE("Directory contents:");
            struct dirent * entry;
            while ((entry = readdir(dir)) != nullptr) {
                if (entry->d_name[0] != '.') {
                    LOGE("  %s", entry->d_name);
                }
            }
            closedir(dir);
        } else {
            LOGE("Cannot open directory (errno=%d: %s)", errno, strerror(errno));
        }
    }

    llama_backend_init();
    backend_initialized = true;
    env->ReleaseStringUTFChars(nativeLibDir, lib_dir);

    return n_backends > 0 ? JNI_TRUE : JNI_FALSE;
}

// ---------------------------------------------------------------------------
// loadModel  — Load a GGUF model from disk and create an inference context.
// ---------------------------------------------------------------------------
extern "C"
JNIEXPORT jboolean JNICALL
Java_com_theorangeshade_onenm_1local_1llm_OneNmNative_loadModel(
        JNIEnv * env,
        jobject thiz,
        jstring modelPath,
        jstring nativeLibDir) {

    const char * path = env->GetStringUTFChars(modelPath, nullptr);
    const char * lib_dir = env->GetStringUTFChars(nativeLibDir, nullptr);
    LOGI("loadModel called with path: %s", path);
    LOGI("Native lib dir: %s", lib_dir);

    // Verify file exists and is readable before handing to llama.cpp.
    FILE * f = fopen(path, "rb");
    if (!f) {
        LOGE("Cannot open file: %s", path);
        env->ReleaseStringUTFChars(modelPath, path);
        env->ReleaseStringUTFChars(nativeLibDir, lib_dir);
        return JNI_FALSE;
    }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fclose(f);
    LOGI("File size: %ld bytes", size);

    // Ensure backend is initialized (may already be done via initBackend).
    if (!backend_initialized) {
        LOGI("Backend not pre-initialized, initializing now...");
        llama_log_set(llama_log_callback, nullptr);
        ggml_backend_load_all_from_path(lib_dir);
        LOGI("Backends loaded: %zu", ggml_backend_reg_count());
        llama_backend_init();
        backend_initialized = true;
    } else {
        LOGI("Backend already initialized (%zu backends)", ggml_backend_reg_count());
    }
    env->ReleaseStringUTFChars(nativeLibDir, lib_dir);

    LOGI("Loading model from file...");
    llama_model_params model_params = llama_model_default_params();
    model = llama_model_load_from_file(path, model_params);

    if (!model) {
        LOGE("Failed to load model from: %s", path);
        env->ReleaseStringUTFChars(modelPath, path);
        return JNI_FALSE;
    }
    LOGI("Model loaded successfully");

    LOGI("Creating context...");
    llama_context_params ctx_params = llama_context_default_params();
    ctx = llama_init_from_model(model, ctx_params);

    env->ReleaseStringUTFChars(modelPath, path);

    if (ctx) {
        LOGI("Context created successfully");
    } else {
        LOGE("Failed to create context");
    }

    return ctx != nullptr ? JNI_TRUE : JNI_FALSE;
}

// ---------------------------------------------------------------------------
// generate  — Run inference on a prompt and return generated text.
//
// Steps:
//  1. Clear the KV cache so the full prompt is decoded fresh each call.
//  2. Tokenise the prompt.
//  3. Feed tokens through the model (prefill / decode).
//  4. Build a sampler chain: repeat_penalty → top_k → top_p → temp → dist.
//  5. Sample tokens in a loop until EOS or maxTokens is reached.
// ---------------------------------------------------------------------------
extern "C"
JNIEXPORT jstring JNICALL
Java_com_theorangeshade_onenm_1local_1llm_OneNmNative_generate(
        JNIEnv * env,
        jobject thiz,
        jstring prompt,
        jfloat temperature,
        jint topK,
        jfloat topP,
        jint maxTokens,
        jfloat repeatPenalty) {

    if (!ctx || !model) {
        return env->NewStringUTF("Model not loaded");
    }

    const char * prompt_chars = env->GetStringUTFChars(prompt, nullptr);
    std::string prompt_str(prompt_chars);
    LOGI("generate called with prompt: %s", prompt_chars);
    LOGI("settings: temp=%.2f top_k=%d top_p=%.2f max=%d repeat=%.2f",
         (float)temperature, (int)topK, (float)topP, (int)maxTokens, (float)repeatPenalty);

    const llama_vocab * vocab = llama_model_get_vocab(model);

    // Clear model memory so the full conversation prompt is decoded fresh.
    // This is essential for multi-turn chat: each call sends the entire
    // conversation history, so stale state would corrupt output.
    llama_memory_clear(llama_get_memory(ctx), true);

    // Tokenize the prompt
    int n = prompt_str.size() + 128;
    std::vector<llama_token> tokens(n);

    int token_count = llama_tokenize(
            vocab,
            prompt_str.c_str(),
            prompt_str.length(),
            tokens.data(),
            tokens.size(),
            true,
            true);

    tokens.resize(token_count);
    LOGI("Tokenized prompt: %d tokens", token_count);

    // Decode the prompt
    llama_batch batch = llama_batch_get_one(tokens.data(), tokens.size());
    if (llama_decode(ctx, batch) != 0) {
        LOGE("Failed to decode prompt");
        env->ReleaseStringUTFChars(prompt, prompt_chars);
        return env->NewStringUTF("Error: failed to decode prompt");
    }

    // Set up sampler chain.  Order matters:
    // penalties → top-k → top-p → temperature → distribution sampling.
    auto sparams = llama_sampler_chain_default_params();
    struct llama_sampler * smpl = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(smpl, llama_sampler_init_penalties(
            64, repeatPenalty, 0.0f, 0.0f));
    llama_sampler_chain_add(smpl, llama_sampler_init_top_k(topK));
    llama_sampler_chain_add(smpl, llama_sampler_init_top_p(topP, 1));
    llama_sampler_chain_add(smpl, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(smpl, llama_sampler_init_dist(42));

    std::string result;

    // Auto-regressive generation loop.
    for (int i = 0; i < (int)maxTokens; i++) {
        llama_token new_token = llama_sampler_sample(smpl, ctx, -1);

        // Check for end of generation
        if (llama_vocab_is_eog(vocab, new_token)) {
            LOGI("EOS reached after %d tokens", i);
            break;
        }

        // Convert token to text
        char piece[256];
        int len = llama_token_to_piece(
                vocab,
                new_token,
                piece,
                sizeof(piece),
                0,
                true);

        if (len > 0) {
            result.append(piece, len);
        }

        // Prepare next batch with the sampled token
        llama_batch next_batch = llama_batch_get_one(&new_token, 1);
        if (llama_decode(ctx, next_batch) != 0) {
            LOGE("Failed to decode at token %d", i);
            break;
        }
    }

    llama_sampler_free(smpl);
    env->ReleaseStringUTFChars(prompt, prompt_chars);

    LOGI("Generated %zu chars", result.size());
    return env->NewStringUTF(result.c_str());
}

// ---------------------------------------------------------------------------
// releaseModel  — Free all native resources.
// ---------------------------------------------------------------------------
extern "C"
JNIEXPORT void JNICALL
Java_com_theorangeshade_onenm_1local_1llm_OneNmNative_releaseModel(
        JNIEnv * env,
        jobject thiz) {

    if (ctx) {
        llama_free(ctx);
        ctx = nullptr;
    }

    if (model) {
        llama_model_free(model);
        model = nullptr;
    }

    llama_backend_free();
    backend_initialized = false;
}