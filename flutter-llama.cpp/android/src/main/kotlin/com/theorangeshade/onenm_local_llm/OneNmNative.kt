// Copyright 2026 1nm. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

package com.theorangeshade.onenm_local_llm

/**
 * JNI bridge to the native llama.cpp backend.
 *
 * All methods declared here are implemented in `onenm_bridge.cpp`.
 * The companion `init` block loads the required shared libraries in
 * dependency order.
 */
class OneNmNative {
    /**
     * Initialises the ggml backend (CPU, etc.) from shared libraries in [nativeLibDir].
     *
     * Safe to call multiple times — subsequent calls are no-ops.
     * Call this early (before model download) so backend issues surface immediately.
     *
     * @return `true` if at least one backend was discovered.
     */
    external fun initBackend(nativeLibDir: String): Boolean

    /**
     * Loads a GGUF model from [modelPath].
     *
     * [nativeLibDir] is passed so the C++ layer can discover additional
     * ggml backend shared libraries at runtime.
     *
     * @return `true` if the model and context were created successfully.
     */
    external fun loadModel(modelPath: String, nativeLibDir: String): Boolean

    /**
     * Generates a text completion for [prompt].
     *
     * Sampling parameters control the output quality:
     * - [temperature]   — randomness (0 = greedy, >1 = creative)
     * - [topK]          — keep only top-K candidates
     * - [topP]          — nucleus sampling threshold
     * - [maxTokens]     — maximum tokens to generate
     * - [repeatPenalty] — penalise repeated tokens (1.0 = off)
     *
     * @return the generated text (may be empty if decoding fails).
     */
    external fun generate(prompt: String, temperature: Float, topK: Int, topP: Float, maxTokens: Int, repeatPenalty: Float): String

    /** Frees the model, context, and backend resources. */
    external fun releaseModel()

    companion object {
        /**
         * Loads native shared libraries in dependency order.
         *
         * Order matters: ggml-base → ggml → ggml-cpu → llama → onenm_bridge.
         * OpenMP (omp) is loaded first as a transitive dependency.
         */
        init {
            System.loadLibrary("omp")
            System.loadLibrary("ggml")
            System.loadLibrary("ggml-base")
            System.loadLibrary("ggml-cpu-android_armv8.2_1")
            System.loadLibrary("llama")
            System.loadLibrary("onenm_bridge")
        }
    }
}