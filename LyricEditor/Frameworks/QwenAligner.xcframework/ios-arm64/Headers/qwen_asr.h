#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#define SAMPLE_RATE 16000

#define MEL_BINS 128

#define HOP_LENGTH 160

#define WINDOW_SIZE 400

#define VOCAB_SIZE 151936

#define MAX_ENC_LAYERS 24

#define MAX_DEC_LAYERS 28

#define TOKEN_IM_START 151644

#define TOKEN_IM_END 151645

#define TOKEN_ENDOFTEXT 151643

#define TOKEN_AUDIO_START 151669

#define TOKEN_AUDIO_END 151670

#define TOKEN_AUDIO_PAD 151676

#define TOKEN_ASR_TEXT 151704

#define TOKEN_TIMESTAMP 151705

#define CONV_HIDDEN 480

#define CONV_KERNEL 3

/**
 * Opaque handle to the ASR engine.
 */
typedef struct QwenAsrEngine QwenAsrEngine;

/**
 * Opaque handle to streaming state.
 */
typedef struct QwenAsrStreamState QwenAsrStreamState;

typedef int64_t JLong;

typedef void *JNIEnv;

typedef void *JObject;

typedef void *JString;

typedef int32_t JInt;

typedef void *JFloatArray;

typedef void *JByteArray;

typedef float JFloat;

extern void cblas_sgemm(int32_t order,
                        int32_t transa,
                        int32_t transb,
                        int32_t m,
                        int32_t n,
                        int32_t k,
                        float alpha,
                        const float *a,
                        int32_t lda,
                        const float *b,
                        int32_t ldb,
                        float beta,
                        float *c,
                        int32_t ldc);

extern void vDSP_dotpr(const float *a,
                       int32_t a_stride,
                       const float *b,
                       int32_t b_stride,
                       float *result,
                       uint64_t n);

extern void vDSP_vsmul(const float *a,
                       int32_t a_stride,
                       const float *scalar,
                       float *c,
                       int32_t c_stride,
                       uint64_t n);

extern void vDSP_vsma(const float *a,
                      int32_t a_stride,
                      const float *scalar,
                      const float *b,
                      int32_t b_stride,
                      float *c,
                      int32_t c_stride,
                      uint64_t n);

extern void vvexpf(float *dst, const float *src, const int32_t *n);

extern void cblas_sgemm(int32_t order,
                        int32_t transa,
                        int32_t transb,
                        int32_t m,
                        int32_t n,
                        int32_t k,
                        float alpha,
                        const float *a,
                        int32_t lda,
                        const float *b,
                        int32_t ldb,
                        float beta,
                        float *c,
                        int32_t ldc);

/**
 * Load model from a directory path. Returns null on failure.
 */
struct QwenAsrEngine *qwen_asr_load_model(const char *model_dir,
                                          int32_t n_threads,
                                          int32_t verbosity);

/**
 * Transcribe a WAV file. Returns a heap-allocated C string (caller must free with qwen_asr_free_string).
 */
char *qwen_asr_transcribe_file(struct QwenAsrEngine *engine,
                               const char *wav_path);

/**
 * Transcribe raw PCM samples (f32, 16kHz, mono).
 * Returns a heap-allocated C string (caller must free with qwen_asr_free_string).
 */
char *qwen_asr_transcribe_pcm(struct QwenAsrEngine *engine,
                              const float *samples,
                              int32_t n_samples);

/**
 * Transcribe raw WAV buffer (entire file contents including header).
 * Returns a heap-allocated C string (caller must free with qwen_asr_free_string).
 */
char *qwen_asr_transcribe_wav_buffer(struct QwenAsrEngine *engine,
                                     const uint8_t *wav_data,
                                     int32_t wav_len);

/**
 * Set segmentation seconds (0 = no segmentation).
 */
void qwen_asr_set_segment_sec(struct QwenAsrEngine *engine, float sec);

/**
 * Set language (e.g. "English", "Chinese"). Empty string = auto-detect.
 */
int32_t qwen_asr_set_language(struct QwenAsrEngine *engine, const char *language);

/**
 * Free a string returned by qwen_asr_transcribe_*.
 */
void qwen_asr_free_string(char *s);

/**
 * Free the engine.
 */
void qwen_asr_free(struct QwenAsrEngine *engine);

/**
 * Create a new streaming state. Returns null on failure.
 */
struct QwenAsrStreamState *qwen_asr_stream_new(void);

/**
 * Free a streaming state.
 */
void qwen_asr_stream_free(struct QwenAsrStreamState *stream);

/**
 * Reset streaming state for a new utterance (reuses allocations).
 */
void qwen_asr_stream_reset(struct QwenAsrStreamState *stream);

/**
 * Push new audio samples and get incremental text delta.
 *
 * `samples` / `n_samples`: new PCM chunk (f32, 16 kHz, mono).
 * `finalize`: set to 1 to signal end-of-stream and flush remaining tokens.
 *
 * Returns a heap-allocated C string with newly emitted text (may be empty),
 * or null if nothing was emitted. Caller must free with `qwen_asr_free_string`.
 */
char *qwen_asr_stream_push(struct QwenAsrEngine *engine,
                           struct QwenAsrStreamState *stream,
                           const float *samples,
                           int32_t n_samples,
                           int32_t finalize);

/**
 * Get the full accumulated transcription result so far.
 * Returns a heap-allocated C string. Caller must free with `qwen_asr_free_string`.
 */
char *qwen_asr_stream_get_result(struct QwenAsrStreamState *stream);

/**
 * Configure streaming chunk size in seconds (default 2.0).
 */
void qwen_asr_stream_set_chunk_sec(struct QwenAsrEngine *engine, float sec);

/**
 * Configure token rollback window (default 5).
 */
void qwen_asr_stream_set_rollback(struct QwenAsrEngine *engine, int32_t tokens);

/**
 * Configure unfixed chunks count before emitting (default 2).
 */
void qwen_asr_stream_set_unfixed_chunks(struct QwenAsrEngine *engine, int32_t chunks);

/**
 * Configure max new tokens per chunk (default 32).
 */
void qwen_asr_stream_set_max_new_tokens(struct QwenAsrEngine *engine, int32_t tokens);

/**
 * Forced-align reference text against PCM (f32, 16kHz, mono).
 * Returns a heap-allocated JSON C string of the form
 * `[{"text":"...","start_ms":N,"end_ms":N},...]`, or null on failure.
 * Caller must free with `qwen_asr_free_string`.
 */
char *qwen_asr_align_pcm(struct QwenAsrEngine *engine,
                         const float *samples,
                         int32_t n_samples,
                         const char *text,
                         const char *language);

extern int32_t __android_log_write(int32_t prio, const char *tag, const char *text);

/**
 * Load model. Returns native handle as jlong.
 */
JLong Java_com_qwenasr_QAsrEngine_nativeLoadModel(JNIEnv env,
                                                  JObject _obj,
                                                  JString model_dir,
                                                  JInt n_threads);

/**
 * Transcribe PCM float array.
 */
JString Java_com_qwenasr_QAsrEngine_nativeTranscribePcm(JNIEnv env,
                                                        JObject _obj,
                                                        JLong handle,
                                                        JFloatArray samples,
                                                        JInt n_samples);

/**
 * Transcribe WAV byte array.
 */
JString Java_com_qwenasr_QAsrEngine_nativeTranscribeWav(JNIEnv env,
                                                        JObject _obj,
                                                        JLong handle,
                                                        JByteArray wav_data,
                                                        JInt wav_len);

/**
 * Free engine.
 */
void Java_com_qwenasr_QAsrEngine_nativeFree(JNIEnv _env, JObject _obj, JLong handle);

/**
 * Set segment seconds.
 */
void Java_com_qwenasr_QAsrEngine_nativeSetSegmentSec(JNIEnv _env,
                                                     JObject _obj,
                                                     JLong handle,
                                                     JFloat sec);
