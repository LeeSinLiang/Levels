import AppKit
import SwiftUI
import Combine

@MainActor
private final class PopoverLayout: ObservableObject {
    let width: CGFloat = 400
    @Published var height: CGFloat = 351
    @Published var maxRowsHeight: CGFloat = 352
}

/// Uses the full status-button bounds as the native arrow's anchor. The content
/// stays below the menu bar and bounds its scrolling list to the current screen.
@MainActor
final class PopoverController: NSObject, NSPopoverDelegate {
    private let model: MixerModel
    private weak var button: NSStatusBarButton?
    private let popover = NSPopover()
    private let layout = PopoverLayout()
    private var subscriptions = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    var openWindow: (() -> Void)?

    init(model: MixerModel, button: NSStatusBarButton) {
        self.model = model
        self.button = button
        super.init()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        let hosting = NSHostingView(rootView: PopoverContent(model: model, layout: layout,
            dismiss: { [weak self] in self?.close() },
            openWindow: { [weak self] in self?.close(); self?.openWindow?() }))
        hosting.sizingOptions = []
        hosting.frame = NSRect(x: 0, y: 0, width: layout.width, height: layout.height)
        hosting.autoresizingMask = [.width, .height]
        let controller = NSViewController()
        controller.view = hosting
        popover.contentViewController = controller
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLayout() }
            .store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let wasShown = self.popover.isShown
                self.close()
                if wasShown { self.show() }
            }
        }
        updateLayout()
    }

    func show() {
        guard let button, button.window != nil else { return }
        model.refresh()
        updateLayout()
        NSApp.activate(ignoringOtherApps: true)
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        model.panelVisible = true
        popover.contentViewController?.view.window?.title = "Levels Popover"
        popover.contentViewController?.view.window?.makeKey()
    }
    func toggle() { popover.isShown ? close() : show() }
    func close() { popover.performClose(nil) }
    func popoverDidClose(_ notification: Notification) { model.panelVisible = false }

    private func updateLayout() {
        let screen = button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        var availableHeight = (screen?.visibleFrame.height ?? 800) - 24
        if let button, let window = button.window, let screen {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            availableHeight = max(0, anchor.minY - screen.visibleFrame.minY - 24)
        }
        let rows = min(352, max(88, availableHeight - MixerView.fixedHeight(model: model)))
        let height = MixerView.preferredHeight(model: model, maxRowsHeight: rows)
        if layout.maxRowsHeight != rows { layout.maxRowsHeight = rows }
        if layout.height != height { layout.height = height }
        let size = NSSize(width: layout.width, height: height)
        if popover.contentSize != size { popover.contentSize = size }
    }
    func shutdown() {
        subscriptions.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        close()
        popover.delegate = nil
        model.panelVisible = false
    }
}

private struct PopoverContent: View {
    @ObservedObject var model: MixerModel
    @ObservedObject var layout: PopoverLayout
    var dismiss: () -> Void
    var openWindow: () -> Void

    var body: some View {
        MixerView(model: model, width: layout.width, maxRowsHeight: layout.maxRowsHeight,
            surface: .popover, dismiss: dismiss, openWindow: openWindow, quit: { NSApp.terminate(nil) })
            .frame(width: layout.width, height: layout.height, alignment: .top)
            .onExitCommand(perform: dismiss)
    }
}
