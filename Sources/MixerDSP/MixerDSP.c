#include "MixerDSP.h"
#include <stdatomic.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

// The Core Audio callback has no allocations, locks, Objective-C, or Swift ARC.
// Only the IO thread touches current_gain. Other shared fields use lock-free atomics.
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Realtime gain needs lock-free atomics");
_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "Realtime counters need lock-free atomics");
struct MixerDSP {
    _Atomic(float) target_gain;
    _Atomic(float) peak;
    _Atomic(float) max_peak;
    _Atomic(uint64_t) callbacks;
    _Atomic(uint64_t) frames;
    float current_gain;
    float step;
    uint32_t offset;
    bool playback;
};

static float safe_gain(float value) { return isfinite(value) ? fminf(1, fmaxf(0, value)) : 1; }

MixerDSP *mixer_create(float gain, double rate, uint32_t offset, bool playback) {
    MixerDSP *state = calloc(1, sizeof(MixerDSP));
    if (!state) return NULL;
    atomic_init(&state->target_gain, safe_gain(gain));
    atomic_init(&state->peak, 0);
    atomic_init(&state->max_peak, 0);
    atomic_init(&state->callbacks, 0);
    atomic_init(&state->frames, 0);
    state->current_gain = safe_gain(gain);
    state->step = 1.0f / (float)(fmax(8000, rate) * 0.02); // 20 ms full-scale ramp
    state->offset = offset;
    state->playback = playback;
    return state;
}
void mixer_destroy(MixerDSP *state) { free(state); }
void mixer_set_gain(MixerDSP *state, float gain) { atomic_store_explicit(&state->target_gain, safe_gain(gain), memory_order_relaxed); }
float mixer_peak(MixerDSP *state) { return atomic_load_explicit(&state->peak, memory_order_relaxed); }
float mixer_max_peak(MixerDSP *state) { return atomic_load_explicit(&state->max_peak, memory_order_relaxed); }
uint64_t mixer_callback_count(MixerDSP *state) { return atomic_load_explicit(&state->callbacks, memory_order_relaxed); }
uint64_t mixer_frame_count(MixerDSP *state) { return atomic_load_explicit(&state->frames, memory_order_relaxed); }

static uint32_t frames_in_buffer(const AudioBuffer *buffer) {
    if (!buffer->mData || !buffer->mNumberChannels) return 0;
    return buffer->mDataByteSize / (sizeof(float) * buffer->mNumberChannels);
}

// Tap input may be interleaved stereo or two planar buffers. The tap follows
// physical-device inputs in the aggregate, so microphone buffers are skipped.
static float channel_sample(const AudioBufferList *list, uint32_t offset, uint32_t channel, uint32_t frame) {
    uint32_t cursor = 0;
    for (uint32_t b = offset; b < list->mNumberBuffers; ++b) {
        const AudioBuffer *buffer = &list->mBuffers[b];
        if (channel < cursor + buffer->mNumberChannels) {
            if (frame >= frames_in_buffer(buffer)) return 0;
            float value = ((const float *)buffer->mData)[frame * buffer->mNumberChannels + channel - cursor];
            return isfinite(value) ? value : 0;
        }
        cursor += buffer->mNumberChannels;
    }
    return 0;
}

void mixer_process(MixerDSP *state, const AudioBufferList *input, AudioBufferList *output) {
    if (!state) return;
    if (output) {
        for (uint32_t b = 0; b < output->mNumberBuffers; ++b)
            if (output->mBuffers[b].mData) memset(output->mBuffers[b].mData, 0, output->mBuffers[b].mDataByteSize);
    }
    atomic_fetch_add_explicit(&state->callbacks, 1, memory_order_relaxed);
    if (!input || state->offset >= input->mNumberBuffers) return;
    uint32_t frames = frames_in_buffer(&input->mBuffers[state->offset]);
    uint32_t channels = 0;
    for (uint32_t b = state->offset; b < input->mNumberBuffers; ++b) channels += input->mBuffers[b].mNumberChannels;
    if (!channels) return;
    float target = atomic_load_explicit(&state->target_gain, memory_order_relaxed);
    float peak = 0;
    for (uint32_t f = 0; f < frames; ++f) {
        float left = channel_sample(input, state->offset, 0, f);
        float right = channels > 1 ? channel_sample(input, state->offset, 1, f) : left;
        peak = fmaxf(peak, fmaxf(fabsf(left), fabsf(right)));
        float difference = target - state->current_gain;
        state->current_gain += fminf(state->step, fmaxf(-state->step, difference));
        if (!state->playback || !output) continue;
        uint32_t destination_channel = 0;
        uint32_t total_output_channels = 0;
        for (uint32_t b = 0; b < output->mNumberBuffers; ++b) total_output_channels += output->mBuffers[b].mNumberChannels;
        for (uint32_t b = 0; b < output->mNumberBuffers; ++b) {
            AudioBuffer *buffer = &output->mBuffers[b];
            if (f >= frames_in_buffer(buffer)) { destination_channel += buffer->mNumberChannels; continue; }
            float *data = buffer->mData;
            for (uint32_t c = 0; c < buffer->mNumberChannels; ++c, ++destination_channel) {
                float sample = total_output_channels == 1 ? (left + right) * 0.5f
                             : destination_channel == 0 ? left : destination_channel == 1 ? right : 0;
                data[f * buffer->mNumberChannels + c] = sample * state->current_gain;
            }
        }
    }
    atomic_store_explicit(&state->peak, peak, memory_order_relaxed);
    // A single writer owns this maximum; readers only load it.
    float maximum = atomic_load_explicit(&state->max_peak, memory_order_relaxed);
    if (peak > maximum) atomic_store_explicit(&state->max_peak, peak, memory_order_relaxed);
    atomic_fetch_add_explicit(&state->frames, frames, memory_order_relaxed);
}

OSStatus mixer_io_proc(AudioObjectID device, const AudioTimeStamp *now,
                      const AudioBufferList *input, const AudioTimeStamp *input_time,
                      AudioBufferList *output, const AudioTimeStamp *output_time, void *context) {
    mixer_process(context, input, output);
    return noErr;
}
