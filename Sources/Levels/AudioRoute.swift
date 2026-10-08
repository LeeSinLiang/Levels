import CoreAudio
import MixerDSP
import Foundation

final class AudioRoute {
    private(set) var tap: AudioObjectID = 0
    private(set) var device: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var dsp: OpaquePointer?
    private var started = false
    let processIDs: [AudioObjectID]
    let outputUID: String
    var peak: Float { dsp.map(mixer_peak) ?? 0 }
    var maximumPeak: Float { dsp.map(mixer_max_peak) ?? 0 }
    var callbacks: UInt64 { dsp.map(mixer_callback_count) ?? 0 }
    var frames: UInt64 { dsp.map(mixer_frame_count) ?? 0 }

    init(processes: [AudioObjectID], output: OutputDevice, gain: Float, playback: Bool = true) throws {
        processIDs = processes.sorted()
        outputUID = output.uid
        do {
            guard (1...2).contains(output.channels) else {
                throw AudioFailure(operation: "This output has \(output.channels) channels; choose a mono or stereo output", status: kAudioHardwareUnsupportedOperationError)
            }
            let description = CATapDescription(stereoMixdownOfProcesses: processes)
            description.name = "Levels app audio"
            description.uuid = UUID()
            description.isPrivate = true
            // Non-mutating probes leave the original audio path intact. For playback,
            // mute only while IO is actually reading; stop/crash restores the source.
            description.muteBehavior = playback ? .mutedWhenTapped : .unmuted
            try HAL.check(AudioHardwareCreateProcessTap(description, &tap), "Creating app audio tap")
            let format = try HAL.scalar(tap, kAudioTapPropertyFormat, default: AudioStreamBasicDescription())
            guard format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mChannelsPerFrame == 2 else {
                throw AudioFailure(operation: "Unsupported app audio format", status: kAudioHardwareUnsupportedOperationError)
            }
            let tapUID = try HAL.string(tap, kAudioTapPropertyUID)
            // Suppress physical inputs in the aggregate. Only the app's output tap is read.
            let composition: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Levels · private audio route",
                kAudioAggregateDeviceUIDKey: "local.soundmixer.route.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceMainSubDeviceKey: output.uid,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.uid, kAudioSubDeviceInputChannelsKey: 0]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]],
                kAudioAggregateDeviceTapAutoStartKey: false
            ]
            try HAL.check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &device), "Creating app audio route")
            let inputLayout = try HAL.bufferLayout(device, scope: kAudioObjectPropertyScopeInput)
            let tapBuffers = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? 2 : 1
            guard inputLayout.count >= tapBuffers, inputLayout.suffix(tapBuffers).reduce(0, +) == 2 else {
                throw AudioFailure(operation: "Unexpected tap channel layout", status: kAudioHardwareUnsupportedOperationError)
            }
            // Validate the HAL buffers before any source is muted.
            for scope in [kAudioObjectPropertyScopeInput, kAudioObjectPropertyScopeOutput] {
                let streams = try HAL.objects(device, kAudioDevicePropertyStreams, scope: scope)
                for stream in streams {
                    let streamFormat = try HAL.scalar(stream, kAudioStreamPropertyVirtualFormat, default: AudioStreamBasicDescription())
                    guard streamFormat.mFormatID == kAudioFormatLinearPCM, streamFormat.mBitsPerChannel == 32,
                          streamFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0 else {
                        throw AudioFailure(operation: "Unsupported output stream format", status: kAudioHardwareUnsupportedOperationError)
                    }
                }
            }
            let sampleRate = try HAL.scalar(device, kAudioDevicePropertyNominalSampleRate, default: Float64(48000))
            dsp = mixer_create(gain, sampleRate, UInt32(inputLayout.count - tapBuffers), playback)
            guard let dsp else { throw AudioFailure(operation: "Allocating app audio route", status: kAudioHardwareUnspecifiedError) }
            try HAL.check(AudioDeviceCreateIOProcID(device, mixer_io_proc, UnsafeMutableRawPointer(dsp), &ioProc), "Connecting app audio route")
        } catch {
            stop()
            throw error
        }
    }

    func start() throws {
        guard !started, let ioProc else { return }
        try HAL.check(AudioDeviceStart(device, ioProc), "Starting app audio route")
        started = true
    }
    func setGain(_ gain: Float) { if let dsp { mixer_set_gain(dsp, gain) } }
    func stop() {
        if let ioProc {
            if started { AudioDeviceStop(device, ioProc) }
            AudioDeviceDestroyIOProcID(device, ioProc)
        }
        ioProc = nil
        started = false
        if device != 0 { AudioHardwareDestroyAggregateDevice(device); device = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
        if let dsp { mixer_destroy(dsp); self.dsp = nil }
    }
    deinit { stop() }
}
