import AppKit
import AudioToolbox
import CoreAudio
import MixerCore

struct AudioFailure: LocalizedError {
    let operation: String
    let status: OSStatus
    var errorDescription: String? {
        let bits = UInt32(bitPattern: status)
        let bytes = [24, 16, 8, 0].map { UInt8((bits >> $0) & 255) }
        let code = bytes.allSatisfy { (32...126).contains($0) } ? String(bytes: bytes, encoding: .ascii)! : String(status)
        return "\(operation) failed (\(code))."
    }
}

enum HAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }
    static func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw AudioFailure(operation: operation, status: status) }
    }
    static func scalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, default value: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> T {
        var result = value
        var property = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &result) {
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, UnsafeMutableRawPointer($0))
        }
        try check(status, "Reading audio property")
        return result
    }
    static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
        var property = address(selector, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size), "Listing audio objects")
        guard size > 0 else { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = values.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0.baseAddress!) }
        try check(status, "Listing audio objects")
        return Array(values.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var property = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value), "Reading audio name")
        return value?.takeRetainedValue() as String? ?? ""
    }
    static func bufferLayout(_ device: AudioObjectID, scope: AudioObjectPropertyScope) throws -> [UInt32] {
        var property = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size), "Reading channel layout")
        let memory = UnsafeMutableRawPointer.allocate(byteCount: max(Int(size), MemoryLayout<AudioBufferList>.size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        try check(AudioObjectGetPropertyData(device, &property, 0, nil, &size, memory), "Reading channel layout")
        return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self)).map(\.mNumberChannels)
    }
    static func defaultOutput() throws -> AudioObjectID {
        try scalar(system, kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID(0))
    }
    static func setDefaultOutput(_ device: AudioObjectID) throws {
        var property = address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = device
        try check(AudioObjectSetPropertyData(system, &property, 0, nil, UInt32(MemoryLayout.size(ofValue: value)), &value), "Changing output")
    }
    static func processID(for pid: pid_t) throws -> AudioObjectID {
        var property = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var process = AudioObjectID(0)
        var processSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var value = pid
        try check(AudioObjectGetPropertyData(system, &property, UInt32(MemoryLayout<pid_t>.size), &value, &processSize, &process), "Finding audio process")
        return process
    }

    // The virtual main-volume property preserves the device's stereo balance.
    static func masterVolume(_ device: AudioObjectID) -> Double? {
        var property = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeOutput)
        guard AudioObjectHasProperty(device, &property) else { return nil }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &property, &settable) == noErr, settable.boolValue else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }
    static func setMasterVolume(_ device: AudioObjectID, _ volume: Double) throws {
        var property = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeOutput)
        var value = Float32(min(1, max(0, volume)))
        try check(AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &value), "Changing system volume")
    }
}

struct OutputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let channels: UInt32
    static func list() throws -> [OutputDevice] {
        try HAL.objects(HAL.system, kAudioHardwarePropertyDevices).compactMap { id in
            guard let layout = try? HAL.bufferLayout(id, scope: kAudioObjectPropertyScopeOutput), layout.reduce(0, +) > 0,
                  let uid = try? HAL.string(id, kAudioDevicePropertyDeviceUID), !uid.hasPrefix("local.soundmixer."),
                  let name = try? HAL.string(id, kAudioObjectPropertyName) else { return nil }
            let alive = (try? HAL.scalar(id, kAudioDevicePropertyDeviceIsAlive, default: UInt32(0))) ?? 0
            guard alive != 0 else { return nil }
            return OutputDevice(id: id, uid: uid, name: name, channels: layout.reduce(0, +))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct AudioApp: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    var processes: [AudioObjectID]
    var outputDevices: Set<AudioObjectID>
    var isPlaying: Bool

    static func list() throws -> [AudioApp] {
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier != nil && $0.activationPolicy == .regular }
        let bundles = running.compactMap(\.bundleIdentifier)
        var grouped: [String: AudioApp] = [:]
        for object in try HAL.objects(HAL.system, kAudioHardwarePropertyProcessObjectList) {
            guard let pid = try? HAL.scalar(object, kAudioProcessPropertyPID, default: pid_t(0)), pid > 0, pid != getpid() else { continue }
            let bundle = (try? HAL.string(object, kAudioProcessPropertyBundleID)) ?? ""
            // WebKit's GPU audio process is shared. Do not claim a particular tab/app owns it.
            let webkit = bundle.hasPrefix("com.apple.WebKit")
            let ownerBundle = AppIdentity.owner(of: bundle, candidates: bundles)
            let direct = NSRunningApplication(processIdentifier: pid)
            let owner = running.first { $0.bundleIdentifier == ownerBundle } ?? (direct?.activationPolicy == .regular ? direct : nil)
            let active = ((try? HAL.scalar(object, kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) ?? 0) != 0
            let devices = Set((try? HAL.objects(object, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput)) ?? [])
            // Keep recognised applications while idle, but omit background HAL services.
            guard owner != nil || webkit || active else { continue }
            if bundle == "com.apple.audio.coreaudiod" || bundle.hasPrefix("local.soundmixer.") { continue }
            let key = webkit ? "com.apple.WebKit.Audio" : owner?.bundleIdentifier ?? (bundle.isEmpty ? "process.\(pid)" : bundle)
            let name = webkit ? "Safari & Web Audio" : owner?.localizedName ?? direct?.localizedName ?? (bundle.isEmpty ? "Audio process \(pid)" : bundle.components(separatedBy: ".").last!)
            let icon = webkit ? NSWorkspace.shared.icon(for: .html) : owner?.icon ?? direct?.icon
            if var app = grouped[key] {
                app.processes.append(object)
                app.isPlaying = app.isPlaying || active
                app.outputDevices.formUnion(devices)
                grouped[key] = app
            } else {
                grouped[key] = AudioApp(id: key, name: name, icon: icon, processes: [object], outputDevices: devices, isPlaying: active)
            }
        }
        return grouped.values.map { app in var copy = app; copy.processes.sort(); return copy }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
