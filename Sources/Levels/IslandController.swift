import AppKit
import SwiftUI
import Combine
import MixerCore
import QuartzCore

@MainActor
final class IslandPresentation: ObservableObject {
    @Published var expanded = false
    @Published var geometry: IslandGeometry
    @Published var bodyHeight: CGFloat = 340
    @Published var maxRowsHeight: CGFloat = 352

    init(geometry: IslandGeometry) { self.geometry = geometry }
    var frame: CGRect { geometry.frame(expanded: expanded, bodyHeight: bodyHeight) }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var collapse: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { collapse?() }
}

/// A borderless panel has no popover arrow and doesn't steal application focus.
/// Only decorative content lives in the screen's camera-housing band.
@MainActor
final class IslandController {
    private let model: MixerModel
    private let panel: IslandPanel
    private let state: IslandPresentation
    private var subscriptions = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var hovering = false
    private var hoverWork: DispatchWorkItem?
    private var targetFrame: CGRect?
    var openWindow: (() -> Void)?

    init(model: MixerModel) {
        self.model = model
        let screen = Self.targetScreen()
        let geometry = Self.geometry(screen)
        state = IslandPresentation(geometry: geometry)
        panel = IslandPanel(contentRect: geometry.frame(expanded: false, bodyHeight: 0), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Levels Island"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collapse = { [weak self] in self?.setExpanded(false) }
        let hosting = NSHostingView(rootView: IslandView(model: model, state: state,
            toggle: { [weak self] in self?.toggle() },
            hover: { [weak self] inside in self?.hover(inside) },
            collapse: { [weak self] in self?.setExpanded(false) },
            openWindow: { [weak self] in self?.setExpanded(false); self?.openWindow?() }))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: panel.frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLayout(animated: true) }
            .store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateScreen() }
        }
        // Mouse-click monitors do not read keyboard events or need Accessibility.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.collapseIfOutside() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.window !== self?.panel, event.window?.level != .popUpMenu {
                self?.collapseIfOutside()
            }
            return event
        }
        updateLayout(animated: false)
        panel.orderFrontRegardless()
    }

    private static func targetScreen() -> NSScreen {
        // Prefer the physical housing even while another monitor is active.
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }
    private static func geometry(_ screen: NSScreen) -> IslandGeometry {
        IslandGeometry(screen: screen.frame, visibleScreen: screen.visibleFrame, topInset: screen.safeAreaInsets.top, leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea)
    }
    func show() { setExpanded(true); panel.makeKeyAndOrderFront(nil) }
    func toggle() {
        let opening = !state.expanded
        setExpanded(opening)
        if opening { panel.makeKeyAndOrderFront(nil) }
    }
    func collapse() { setExpanded(false) }
    private func setExpanded(_ expanded: Bool) {
        hoverWork?.cancel()
        guard state.expanded != expanded else {
            if expanded { panel.orderFrontRegardless() }
            return
        }
        state.expanded = expanded
        model.panelVisible = expanded
        if expanded { model.refresh() }
        else if panel.isKeyWindow {
            // Release keyboard focus, then keep the compact island visible
            // without taking focus away from the underlying application.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        updateLayout(animated: true)
    }
    private func hover(_ inside: Bool) {
        hovering = inside
        hoverWork?.cancel()
        // A short dwell makes the notch useful without flashing open when the
        // pointer merely crosses the menu bar. Once open, it stays for sliders.
        guard inside, !state.expanded else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hovering else { return }
            self.setExpanded(true)
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    private func collapseIfOutside() {
        guard state.expanded, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        setExpanded(false)
    }
    private func updateScreen() {
        state.geometry = Self.geometry(Self.targetScreen())
        updateLayout(animated: false)
    }
    private func updateLayout(animated: Bool) {
        let fixedHeight = MixerView.fixedHeight(model: model)
        let rowsHeight = min(352, max(88, state.geometry.availableHeight - state.geometry.capHeight - fixedHeight))
        if state.maxRowsHeight != rowsHeight { state.maxRowsHeight = rowsHeight }
        let bodyHeight = MixerView.preferredHeight(model: model, maxRowsHeight: rowsHeight)
        if state.bodyHeight != bodyHeight { state.bodyHeight = bodyHeight }
        let frame = state.frame
        guard targetFrame != frame else { return }
        targetFrame = frame
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animated && !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [weak panel] in panel?.invalidateShadow() }
        } else { panel.setFrame(frame, display: true); panel.invalidateShadow() }
    }
    func shutdown() {
        hoverWork?.cancel()
        model.panelVisible = false
        subscriptions.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        panel.orderOut(nil)
    }
}

private struct IslandView: View {
    @ObservedObject var model: MixerModel
    @ObservedObject var state: IslandPresentation
    var toggle: () -> Void
    var hover: (Bool) -> Void
    var collapse: () -> Void
    var openWindow: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button(action: toggle) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MixerStyle.accent)
                        .frame(maxWidth: .infinity).frame(height: state.geometry.capHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.expanded ? "Collapse Levels" : "Expand Levels")
                .help(state.expanded ? "Collapse mixer" : "Open app volumes")
                if state.geometry.hasNotch {
                    Color.clear.frame(width: state.geometry.notchWidth).allowsHitTesting(false).accessibilityHidden(true)
                }
                Button(action: toggle) {
                    HStack(spacing: 5) {
                        Circle().fill(model.access == .ready ? MixerStyle.accent : MixerStyle.secondary).frame(width: 4, height: 4)
                        Text("\(model.apps.filter(\.isPlaying).count)")
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(.white)
                    }.frame(maxWidth: .infinity).frame(height: state.geometry.capHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(model.apps.filter(\.isPlaying).count) active apps. \(state.expanded ? "Collapse" : "Expand") mixer")
            }
            .frame(height: state.geometry.capHeight)
            if state.expanded {
                MixerView(model: model, width: state.frame.width, maxRowsHeight: state.maxRowsHeight, dismiss: collapse, openWindow: openWindow, quit: { NSApp.terminate(nil) })
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        .frame(width: state.frame.width, height: state.frame.height, alignment: .top)
        .background(.black)
        .clipShape(IslandShape(attached: state.geometry.hasNotch))
        .contentShape(IslandShape(attached: state.geometry.hasNotch))
        .onHover(perform: hover)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: state.expanded)
    }
}

private struct IslandShape: Shape {
    var attached: Bool
    func path(in rect: CGRect) -> Path {
        let top: CGFloat = attached ? 5 : 22
        let bottom: CGFloat = min(26, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + top), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bottom), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
