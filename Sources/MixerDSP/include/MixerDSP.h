#ifndef MIXER_DSP_H
#define MIXER_DSP_H
#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include <stdint.h>

CF_ASSUME_NONNULL_BEGIN
typedef struct MixerDSP MixerDSP;
MixerDSP * _Nullable mixer_create(float gain, double sample_rate, uint32_t tap_buffer_offset, bool playback);
void mixer_destroy(MixerDSP *state);
void mixer_set_gain(MixerDSP *state, float gain);
float mixer_peak(MixerDSP *state);
float mixer_max_peak(MixerDSP *state);
uint64_t mixer_callback_count(MixerDSP *state);
uint64_t mixer_frame_count(MixerDSP *state);
void mixer_process(MixerDSP *state, const AudioBufferList * _Nullable input, AudioBufferList * _Nullable output);
OSStatus mixer_io_proc(AudioObjectID device, const AudioTimeStamp *now,
                      const AudioBufferList *input, const AudioTimeStamp *input_time,
                      AudioBufferList *output, const AudioTimeStamp *output_time, void * _Nullable context);
CF_ASSUME_NONNULL_END
#endif
