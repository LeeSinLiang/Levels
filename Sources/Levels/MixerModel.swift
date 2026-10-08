import AppKit
import Combine
import CoreAudio
import MixerCore

@MainActor
final class MixerModel: ObservableObject {
    enum Access: Equatable { case unchecked, checking, ready, unavailable }
    @Published var apps: [AudioApp] = []
    @Published var devices: [OutputDevice] = []
    @Published var outputID: AudioObjectID = 0
    @Published var masterVolume: Double? = nil
    @Published var access: Access = .unchecked
    @Published var message: String?
    @Published var appErrors: [String: String] = [:]
    @Published var levels: [String: VolumeSetting] = [:]
    @Published var presentationMode = MixerPresentation(rawValue: UserDefaults.standard.string(forKey: "presentationMode") ?? "") ?? .dynamicIsland {
        didSet { UserDefaults.standard.set(presentationMode.rawValue, forKey: "presentationMode") }
    }
    @Published var showInactive = UserDefaults.standard.bool(forKey: "showInactive") {
        didSet { UserDefaults.standard.set(showInactive, forKey: "showInactive") }
    }
    @Published var search = ""
    private var routes: [String: AudioRoute] = [:]
    private var lastSeen: [String: Date] = [:]
    private var routeProgress: [String: (frames: UInt64, at: Date)] = [:]
    private var timer: Timer?
    private var permissionTask: Task<Void, Never>?
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var observers: [NSObjectProtocol] = []
    private var suspended = false
    var panelVisible = false

    var output: OutputDevice? { devices.first { $0.id == outputID } }
    var visibleApps: [AudioApp] {
        apps.filter { app in
            let recent = Date().timeIntervalSince(lastSeen[app.id] ?? .distantPast) < 20
            let visible = showInactive || app.isPlaying || setting(app.id).needsProcessing || recent
            return visible && (search.isEmpty || app.name.localizedCaseInsensitiveContains(search))
        }.sorted { first, second in
            if first.isPlaying != second.isPlaying { return first.isPlaying }
            let order = first.name.localizedStandardCompare(second.name)
            return order == .orderedSame ? first.id < second.id : order == .orderedAscending
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "appLevels"),
           let saved = try? JSONDecoder().decode([String: VolumeSetting].self, from: data) {
            levels = saved.mapValues { VolumeSetting(volume: $0.volume, muted: $0.muted) }
        }
        refresh()
        for selector in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            var property = HAL.address(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
            if AudioObjectAddPropertyListenerBlock(HAL.system, &property, .main, block) == noErr { listeners.append((property, block)) }
        }
        // Activity properties don't always issue reliable notifications; a 1 s
        // scan also handles app audio-process replacements and volume-key changes.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.suspended = true
                self?.permissionTask?.cancel()
                self?.access = .unchecked
                self?.releaseRoutes()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.suspended = false
                self.access = .unchecked
                self.message = nil
                if UserDefaults.standard.bool(forKey: "mixingEnabled") { self.checkAccess() }
            }
        })
        if UserDefaults.standard.bool(forKey: "mixingEnabled") {
            DispatchQueue.main.async { [weak self] in self?.checkAccess() }
        }
    }

    func setting(_ id: String) -> VolumeSetting { levels[id] ?? VolumeSetting() }
    func setVolume(_ id: String, _ volume: Double) {
        var value = setting(id)
        value.volume = min(1, max(0, volume))
        // A deliberate slider movement restores sound after muting.
        if volume > 0 { value.muted = false }
        update(id, value)
    }
    func toggleMute(_ id: String) {
        var value = setting(id)
        value.muted.toggle()
        update(id, value)
    }
    func reset(_ id: String) { update(id, VolumeSetting()) }
    func resetAll() {
        releaseRoutes()
        levels.removeAll()
        appErrors.removeAll()
        save()
    }
    private func update(_ id: String, _ setting: VolumeSetting) {
        levels[id] = setting
        appErrors.removeValue(forKey: id)
        save()
        reconcile()
    }
    private func save() {
        if let data = try? JSONEncoder().encode(levels) { UserDefaults.standard.set(data, forKey: "appLevels") }
    }
    func setMaster(_ value: Double) {
        do {
            try HAL.setMasterVolume(outputID, value)
            masterVolume = value
        } catch { message = error.localizedDescription }
    }
    func selectOutput(_ id: AudioObjectID) {
        guard id != outputID else { return }
        releaseRoutes()
        do {
            try HAL.setDefaultOutput(id)
            appErrors.removeAll()
            refresh()
        } catch { message = error.localizedDescription; refresh() }
    }
    func refresh() {
        do {
            let freshDevices = try OutputDevice.list()
            let freshOutput = try HAL.defaultOutput()
            if outputID != freshOutput { releaseRoutes(); appErrors.removeAll() }
            devices = freshDevices
            outputID = freshOutput
            masterVolume = HAL.masterVolume(outputID)
            let freshApps = try AudioApp.list()
            for app in freshApps where app.isPlaying { lastSeen[app.id] = Date() }
            apps = freshApps
            reconcile()
        } catch { message = error.localizedDescription }
    }
    private func reconcile() {
        guard !suspended, access == .ready else { return }
        let ids = Set(apps.map(\.id))
        for id in Array(routes.keys) where !ids.contains(id) { removeRoute(id) }
        for app in apps {
            let value = setting(app.id)
            guard value.needsProcessing else { removeRoute(app.id); continue }
            guard appErrors[app.id] == nil else { continue }
            // Follow an app's actual output if it uses one identifiable device.
            // Multiple destinations cannot be reproduced faithfully by one stereo tap.
            let appDevices = devices.filter { app.outputDevices.contains($0.id) }
            if appDevices.count > 1 {
                removeRoute(app.id)
                appErrors[app.id] = "This app uses several outputs. Choose one output in the app, then retry."
                continue
            }
            guard let destination = appDevices.first ?? output else { continue }
            if let existing = routes[app.id], existing.processIDs != app.processes || existing.outputUID != destination.uid {
                removeRoute(app.id)
            }
            if let route = routes[app.id] {
                route.setGain(value.gain)
                let progress = routeProgress[app.id]
                if progress == nil || progress!.frames != route.frames || !app.isPlaying {
                    routeProgress[app.id] = (route.frames, Date())
                } else if Date().timeIntervalSince(progress!.at) > 3 {
                    removeRoute(app.id)
                    appErrors[app.id] = "The audio route stopped responding. Original audio restored; retry this app."
                }
            } else {
                do {
                    let route = try AudioRoute(processes: app.processes, output: destination, gain: value.gain)
                    try route.start()
                    routes[app.id] = route
                    routeProgress[app.id] = (route.frames, Date())
                } catch { appErrors[app.id] = error.localizedDescription }
            }
        }
    }
    func retry(_ id: String) { removeRoute(id); appErrors.removeValue(forKey: id); refresh() }
    func checkAccess() {
        guard access != .checking else { return }
        guard let output else { message = "Connect an audio output first."; return }
        releaseRoutes()
        access = .checking
        message = nil
        permissionTask = Task { [weak self] in
            do {
                let available = try await AudioAccessProbe.check(output: output)
                guard !Task.isCancelled, let self else { return }
                self.access = available ? .ready : .unavailable
                if available { UserDefaults.standard.set(true, forKey: "mixingEnabled") }
                if !available { self.message = "Allow Levels in System Settings → Privacy & Security → Screen & System Audio Recording, then check again." }
                self.appErrors.removeAll()
                self.refresh()
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.access = .unavailable
                self.message = error.localizedDescription
            }
        }
    }
    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
    }
    func openSetupGuide() {
        if let guide = Bundle.main.url(forResource: "Start Here", withExtension: "html") {
            NSWorkspace.shared.open(guide)
        }
    }
    func suspendMixing() {
        permissionTask?.cancel()
        releaseRoutes()
        access = .unchecked
        message = nil
        UserDefaults.standard.set(false, forKey: "mixingEnabled")
    }
    private func removeRoute(_ id: String) {
        routes.removeValue(forKey: id)?.stop()
        routeProgress.removeValue(forKey: id)
    }
    private func releaseRoutes() {
        for route in routes.values { route.stop() }
        routes.removeAll()
        routeProgress.removeAll()
    }
    func shutdown() {
        suspended = true
        access = .unchecked
        permissionTask?.cancel()
        timer?.invalidate()
        for (var property, block) in listeners { AudioObjectRemovePropertyListenerBlock(HAL.system, &property, .main, block) }
        listeners.removeAll()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        releaseRoutes()
    }
}
