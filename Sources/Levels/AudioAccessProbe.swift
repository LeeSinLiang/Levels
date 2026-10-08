import AVFoundation
import CoreAudio

@MainActor
enum AudioAccessProbe {
    static func check(output: OutputDevice) async throws -> Bool {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
        buffer.frameLength = buffer.frameCapacity
        // A near-silent -90 dBFS test signal proves actual capture access. The test
        // taps only this app, never mutes another app, and never writes audio to disk.
        for frame in 0..<Int(buffer.frameLength) {
            let value = Float(sin(Double(frame) * 2 * .pi * 997 / 48000)) * 0.0000316
            buffer.floatChannelData![0][frame] = value
            buffer.floatChannelData![1][frame] = value
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        var route: AudioRoute?
        defer {
            player.stop()
            route?.stop()
            engine.stop()
        }
        try engine.start()
        var process: AudioObjectID = 0
        for _ in 0..<15 {
            process = (try? HAL.processID(for: getpid())) ?? 0
            if process != 0 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard process != 0 else { throw AudioFailure(operation: "Finding the audio test process", status: kAudioHardwareBadObjectError) }
        route = try AudioRoute(processes: [process], output: output, gain: 0, playback: false)
        try route!.start()
        player.play()
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if route!.maximumPeak > 0.000001, route!.frames > 0 { return true }
        }
        return false
    }
}
