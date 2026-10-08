import AppKit
import SwiftUI
import CoreAudio
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    private var island: IslandController?
    private var popover: PopoverController?
    private var presentationSubscription: AnyCancellable?
    private var window: NSWindow?
    private var model: MixerModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--list") {
            do {
                let devices = try OutputDevice.list()
                let current = try HAL.defaultOutput()
                let apps = try AudioApp.list()
                let info: [String: Any] = [
                    "outputDevices": devices.map { ["id": $0.id, "uid": $0.uid, "name": $0.name, "channels": $0.channels, "default": $0.id == current] as [String: Any] },
                    "masterVolume": HAL.masterVolume(current) as Any? ?? NSNull(),
                    "applications": apps.map { ["id": $0.id, "name": $0.name, "processes": $0.processes, "active": $0.isPlaying, "outputs": Array($0.outputDevices)] as [String: Any] }
                ]
                let data = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8)!)
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--check-audio-access") {
            Task { @MainActor in
                do {
                    let current = try HAL.defaultOutput()
                    guard let output = try OutputDevice.list().first(where: { $0.id == current }) else {
                        throw AudioFailure(operation: "Finding the default output", status: kAudioHardwareBadDeviceError)
                    }
                    let available = try await AudioAccessProbe.check(output: output)
                    let result = ["audioAccess": available ? "allowed" : "unavailable", "output": output.name]
                    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                    print(String(decoding: data, as: UTF8.self))
                    exit(available ? EXIT_SUCCESS : EXIT_FAILURE)
                } catch {
                    fputs("\(error.localizedDescription)\n", stderr)
                    exit(EXIT_FAILURE)
                }
            }
            return
        }
        let model = MixerModel()
        self.model = model
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        item.button?.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Levels")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Levels — per-app volume"
        item.button?.target = self
        item.button?.action = #selector(toggleMixer)
        applyPresentation(model.presentationMode, open: false)
        presentationSubscription = model.$presentationMode.dropFirst().removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in self?.applyPresentation(mode, open: true) }
        DispatchQueue.main.async { [weak self] in
            if CommandLine.arguments.contains("--window") { self?.showWindow() }
            else { self?.showMixer() }
        }
    }
    @objc private func toggleMixer() {
        if let island { island.toggle() }
        else { popover?.toggle() }
    }
    private func showMixer() {
        if let island { island.show() }
        else { popover?.show() }
    }
    private func applyPresentation(_ mode: MixerPresentation, open: Bool) {
        guard let model, let button = item?.button else { return }
        island?.shutdown()
        island = nil
        popover?.shutdown()
        popover = nil
        switch mode {
        case .dynamicIsland:
            let island = IslandController(model: model)
            island.openWindow = { [weak self] in self?.showWindow() }
            self.island = island
        case .menuPopover:
            let popover = PopoverController(model: model, button: button)
            popover.openWindow = { [weak self] in self?.showWindow() }
            self.popover = popover
        }
        if open {
            window?.orderOut(nil)
            showMixer()
        }
    }
    private func showWindow() {
        island?.collapse()
        popover?.close()
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let model else { return }
        let view = MixerView(model: model, surface: .popover, openWindow: { [weak self] in self?.showWindow() }, quit: { NSApp.terminate(nil) })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Levels"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMixer()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        presentationSubscription?.cancel()
        island?.shutdown()
        popover?.shutdown()
        model?.shutdown()
    }
}

@main
enum LevelsMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}
