import Foundation
import CoreAudio
import CoreGraphics
import MixerDSP
import MixerCore

private final class Buffers {
    let list: UnsafeMutableAudioBufferListPointer
    let storage: [UnsafeMutablePointer<Float>]
    let memory: UnsafeMutableRawPointer
    let frames: Int
    init(channels: [Int], frames: Int, samples: [[Float]] = []) {
        self.frames = frames
        memory = .allocate(byteCount: MemoryLayout<AudioBufferList>.size + max(0, channels.count - 1) * MemoryLayout<AudioBuffer>.size, alignment: MemoryLayout<AudioBufferList>.alignment)
        let pointer = memory.assumingMemoryBound(to: AudioBufferList.self)
        pointer.initialize(to: AudioBufferList(mNumberBuffers: UInt32(channels.count), mBuffers: AudioBuffer()))
        list = UnsafeMutableAudioBufferListPointer(pointer)
        list.unsafeMutablePointer.pointee.mNumberBuffers = UInt32(channels.count)
        storage = channels.map { UnsafeMutablePointer<Float>.allocate(capacity: frames * $0) }
        for i in channels.indices {
            storage[i].initialize(repeating: 0, count: frames * channels[i])
            if samples.indices.contains(i) {
                for j in 0..<min(samples[i].count, frames * channels[i]) { storage[i][j] = samples[i][j] }
            }
            list[i] = AudioBuffer(mNumberChannels: UInt32(channels[i]), mDataByteSize: UInt32(frames * channels[i] * MemoryLayout<Float>.size), mData: storage[i])
        }
    }
    func values(_ buffer: Int = 0) -> [Float] {
        Array(UnsafeBufferPointer(start: storage[buffer], count: frames * Int(list[buffer].mNumberChannels)))
    }
    deinit {
        for pointer in storage { pointer.deallocate() }
        memory.deallocate()
    }
}

func independentVolumeAndMute() {
    let input = Buffers(channels: [2], frames: 2, samples: [[0.8, -0.6, 0.4, -0.2]])
    let halfOutput = Buffers(channels: [2], frames: 2)
    let fullOutput = Buffers(channels: [2], frames: 2)
    let half = mixer_create(0.5, 48000, 0, true)!
    let full = mixer_create(1, 48000, 0, true)!
    defer { mixer_destroy(half); mixer_destroy(full) }
    mixer_process(half, input.list.unsafeMutablePointer, halfOutput.list.unsafeMutablePointer)
    mixer_process(full, input.list.unsafeMutablePointer, fullOutput.list.unsafeMutablePointer)
    expect(halfOutput.values() == [0.4, -0.3, 0.2, -0.1])
    expect(fullOutput.values() == input.values())
    expect(mixer_max_peak(half) == 0.8)
    expect(mixer_callback_count(half) == 1)
    expect(mixer_frame_count(half) == 2)
}

func muteIsSilentAtStartup() {
    let input = Buffers(channels: [2], frames: 3, samples: [[1, 1, 0.5, -0.5, -1, -1]])
    let output = Buffers(channels: [2], frames: 3, samples: [[1, 1, 1, 1, 1, 1]])
    let dsp = mixer_create(0, 48000, 0, true)!
    defer { mixer_destroy(dsp) }
    mixer_process(dsp, input.list.unsafeMutablePointer, output.list.unsafeMutablePointer)
    expect(output.values().allSatisfy { $0 == 0 })
}

func stereoPlanarAndInterleavedAreEquivalent() {
    let input = Buffers(channels: [1, 1], frames: 3, samples: [[0.2, 0.4, 0.6], [-0.2, -0.4, -0.6]])
    let interleaved = Buffers(channels: [2], frames: 3)
    let planar = Buffers(channels: [1, 1], frames: 3)
    let dsp = mixer_create(1, 48000, 0, true)!
    defer { mixer_destroy(dsp) }
    mixer_process(dsp, input.list.unsafeMutablePointer, interleaved.list.unsafeMutablePointer)
    mixer_process(dsp, input.list.unsafeMutablePointer, planar.list.unsafeMutablePointer)
    expect(interleaved.values() == [0.2, -0.2, 0.4, -0.4, 0.6, -0.6])
    expect(planar.values(0) == input.values(0))
    expect(planar.values(1) == input.values(1))
}

func microphoneInputIsSkipped() {
    let input = Buffers(channels: [1, 2], frames: 2, samples: [[1, 1], [0.1, 0.2, 0.3, 0.4]])
    let output = Buffers(channels: [2], frames: 2)
    let dsp = mixer_create(1, 48000, 1, true)!
    defer { mixer_destroy(dsp) }
    mixer_process(dsp, input.list.unsafeMutablePointer, output.list.unsafeMutablePointer)
    expect(output.values() == input.values(1))
    expect(mixer_max_peak(dsp) == 0.4)
}

func monoOutputDownmixesStereo() {
    let input = Buffers(channels: [2], frames: 2, samples: [[0.8, 0.4, -0.6, 0.2]])
    let output = Buffers(channels: [1], frames: 2)
    let dsp = mixer_create(1, 48000, 0, true)!
    defer { mixer_destroy(dsp) }
    mixer_process(dsp, input.list.unsafeMutablePointer, output.list.unsafeMutablePointer)
    expect(abs(output.values()[0] - 0.6) < 0.00001)
    expect(abs(output.values()[1] + 0.2) < 0.00001)
}

func outputBoundsAndUnusedChannelsAreCleared() {
    let input = Buffers(channels: [2], frames: 4, samples: [[1, 1, 1, 1, 1, 1, 1, 1]])
    let output = Buffers(channels: [4], frames: 2)
    let dsp = mixer_create(1, 48000, 0, true)!
    defer { mixer_destroy(dsp) }
    mixer_process(dsp, input.list.unsafeMutablePointer, output.list.unsafeMutablePointer)
    expect(output.values() == [1, 1, 0, 0, 1, 1, 0, 0])
}

func gainChangesRampWithoutOvershoot() {
    let input = Buffers(channels: [2], frames: 1200, samples: [Array(repeating: 1, count: 2400)])
    let output = Buffers(channels: [2], frames: 1200)
    let dsp = mixer_create(1, 48000, 0, true)!
    defer { mixer_destroy(dsp) }
    mixer_set_gain(dsp, 0)
    mixer_process(dsp, input.list.unsafeMutablePointer, output.list.unsafeMutablePointer)
    let values = output.values()
    expect(values[0] > 0.99 && values[0] < 1)
    expect(values.last == 0)
    expect(values.allSatisfy { (0...1).contains($0) })
    for i in stride(from: 2, to: values.count, by: 2) { expect(values[i] <= values[i - 2]) }
}

func nonFiniteInputCannotReachSpeakers() {
    let input = Buffers(channels: [2], frames: 2, samples: [[.nan, .infinity, -.infinity, 0.5]])
    let output = Buffers(channels: [2], frames: 2)
    let dsp = mixer_create(1, 48000, 0, true)!
    defer { mixer_destroy(dsp) }
    mixer_process(dsp, input.list.unsafeMutablePointer, output.list.unsafeMutablePointer)
    expect(output.values() == [0, 0, 0, 0.5])
}

func probeNeverReplaysAudio() {
    let input = Buffers(channels: [2], frames: 2, samples: [[0.25, 0.25, 0.25, 0.25]])
    let output = Buffers(channels: [2], frames: 2, samples: [[1, 1, 1, 1]])
    let dsp = mixer_create(1, 48000, 0, false)!
    defer { mixer_destroy(dsp) }
    mixer_process(dsp, input.list.unsafeMutablePointer, output.list.unsafeMutablePointer)
    expect(output.values() == [0, 0, 0, 0])
    expect(mixer_max_peak(dsp) == 0.25)
}

func invalidInputClearsOutput() {
    let output = Buffers(channels: [2], frames: 2, samples: [[1, 1, 1, 1]])
    let dsp = mixer_create(1, 48000, 10, true)!
    defer { mixer_destroy(dsp) }
    mixer_process(dsp, nil, output.list.unsafeMutablePointer)
    expect(output.values() == [0, 0, 0, 0])
}

func volumeSettingsClampAndPersist() throws {
    expect(VolumeSetting(volume: -1).gain == 0)
    expect(VolumeSetting(volume: 2).gain == 1)
    expect(VolumeSetting(volume: .nan).gain == 1)
    expect(!VolumeSetting().needsProcessing)
    let saved = ["com.example.Music": VolumeSetting(volume: 0.35, muted: true)]
    let restored = try JSONDecoder().decode([String: VolumeSetting].self, from: JSONEncoder().encode(saved))
    expect(restored == saved)
    expect(restored["com.example.Music"]?.gain == 0)
    expect(restored["com.example.Music"]?.volume == 0.35)
}

func helpersResolveToLongestMatchingApp() {
    let candidates = ["com.google.Chrome", "com.example.Editor", "com.example.Editor.Pro"]
    expect(AppIdentity.owner(of: "com.google.Chrome.helper", candidates: candidates) == "com.google.Chrome")
    expect(AppIdentity.owner(of: "com.example.Editor.Pro.helper", candidates: candidates) == "com.example.Editor.Pro")
    expect(AppIdentity.owner(of: "com.example.EditorOther", candidates: candidates) == nil)
}

nonisolated(unsafe) private var failures = 0

func notchIslandKeepsControlsBelowCamera() {
    let screen = CGRect(x: 0, y: 0, width: 1710, height: 1107)
    let geometry = IslandGeometry(screen: screen, visibleScreen: CGRect(x: 0, y: 0, width: 1710, height: 1073), topInset: 33,
        leftArea: CGRect(x: 0, y: 1074, width: 763, height: 33), rightArea: CGRect(x: 948, y: 1074, width: 762, height: 33))
    let frame = geometry.frame(expanded: true, bodyHeight: 307)
    let interactiveBody = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - geometry.capHeight)
    expect(geometry.notchWidth == 185)
    expect(frame.midX == 855.5)
    expect(frame.maxY == screen.maxY)
    expect(interactiveBody.maxY == 1074)
    expect(!interactiveBody.intersects(geometry.notch!))
    expect(screen.contains(frame))
}

func collapsedIslandStraddlesNotch() {
    let geometry = IslandGeometry(screen: CGRect(x: 0, y: 0, width: 1710, height: 1107), visibleScreen: CGRect(x: 0, y: 0, width: 1710, height: 1073), topInset: 33,
        leftArea: CGRect(x: 0, y: 1074, width: 763, height: 33), rightArea: CGRect(x: 948, y: 1074, width: 762, height: 33))
    let frame = geometry.frame(expanded: false, bodyHeight: 400)
    expect(frame.width == 273)
    expect(frame.height == 41)
    expect(geometry.notch!.minX - frame.minX == 44)
    expect(frame.maxX - geometry.notch!.maxX == 44)
}

func externalIslandUsesItsOwnCoordinates() {
    for origin in [CGFloat(-1920), CGFloat(1710)] {
        let screen = CGRect(x: origin, y: 27, width: 1920, height: 1080)
        let geometry = IslandGeometry(screen: screen, visibleScreen: screen, topInset: 0, leftArea: nil, rightArea: nil)
        let frame = geometry.frame(expanded: true, bodyHeight: 400)
        expect(!geometry.hasNotch)
        expect(frame.midX == screen.midX)
        expect(frame.maxY == screen.maxY - 12)
        expect(screen.contains(frame))
    }
}

func islandHeightIsBoundedByDisplay() {
    let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
    let geometry = IslandGeometry(screen: screen, visibleScreen: CGRect(x: 0, y: 48, width: 800, height: 528), topInset: 0, leftArea: nil, rightArea: nil)
    let frame = geometry.frame(expanded: true, bodyHeight: 1200)
    expect(frame.minY == 60)
    expect(frame.maxY == 564)
    expect(screen.contains(frame))
}

private func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !condition() {
        failures += 1
        print("FAIL \(file):\(line)")
    }
}

@main
struct MixerCheckRunner {
    static func main() {
        let checks: [(String, () throws -> Void)] = [
            ("independentVolumeAndMute", independentVolumeAndMute),
            ("muteIsSilentAtStartup", muteIsSilentAtStartup),
            ("stereoPlanarAndInterleavedAreEquivalent", stereoPlanarAndInterleavedAreEquivalent),
            ("microphoneInputIsSkipped", microphoneInputIsSkipped),
            ("monoOutputDownmixesStereo", monoOutputDownmixesStereo),
            ("outputBoundsAndUnusedChannelsAreCleared", outputBoundsAndUnusedChannelsAreCleared),
            ("gainChangesRampWithoutOvershoot", gainChangesRampWithoutOvershoot),
            ("nonFiniteInputCannotReachSpeakers", nonFiniteInputCannotReachSpeakers),
            ("probeNeverReplaysAudio", probeNeverReplaysAudio),
            ("invalidInputClearsOutput", invalidInputClearsOutput),
            ("volumeSettingsClampAndPersist", volumeSettingsClampAndPersist),
            ("helpersResolveToLongestMatchingApp", helpersResolveToLongestMatchingApp),
            ("notchIslandKeepsControlsBelowCamera", notchIslandKeepsControlsBelowCamera),
            ("collapsedIslandStraddlesNotch", collapsedIslandStraddlesNotch),
            ("externalIslandUsesItsOwnCoordinates", externalIslandUsesItsOwnCoordinates),
            ("islandHeightIsBoundedByDisplay", islandHeightIsBoundedByDisplay)
        ]
        for (name, check) in checks {
            let before = failures
            do { try check() } catch { failures += 1; print("FAIL \(name): \(error)") }
            if before == failures { print("PASS \(name)") }
        }
        print("\(checks.count) checks; \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
