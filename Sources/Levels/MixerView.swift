import SwiftUI
import MixerCore

enum MixerStyle {
    static let accent = Color(red: 0.50, green: 0.94, blue: 0.77)
    static let secondary = Color(white: 0.66)
    static let divider = Color.white.opacity(0.12)
}

enum MixerSurface {
    case island, popover

    var background: Color { self == .island ? .black : Color(white: 0.085) }
}

struct MixerView: View {
    @ObservedObject var model: MixerModel
    var width: CGFloat = 430
    var maxRowsHeight: CGFloat = 352
    var surface: MixerSurface = .island
    var dismiss: (() -> Void)? = nil
    var openWindow: () -> Void
    var quit: () -> Void

    static func hasSearch(_ model: MixerModel) -> Bool { model.visibleApps.count > 5 || !model.search.isEmpty }
    static func fixedHeight(model: MixerModel) -> CGFloat {
        52 + 80 + 1 + 42 + 44 + (hasSearch(model) ? 44 : 0)
            + (model.access != .ready ? 162 : model.message != nil ? 56 : 0)
    }
    static func rowsHeight(model: MixerModel, maximum: CGFloat) -> CGFloat {
        if model.visibleApps.isEmpty { return min(132, maximum) }
        return min(model.visibleApps.reduce(CGFloat(0)) { $0 + (model.appErrors[$1.id] == nil ? 88 : 106) }, maximum)
    }
    static func preferredHeight(model: MixerModel, maxRowsHeight: CGFloat) -> CGFloat {
        fixedHeight(model: model) + rowsHeight(model: model, maximum: maxRowsHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: 52)
            outputSection.frame(height: 80)
            if model.access != .ready {
                accessCard.frame(height: 146).padding(.bottom, 16)
            } else if let message = model.message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 22).frame(height: 56)
            }
            Rectangle().fill(MixerStyle.divider).frame(height: 1).padding(.horizontal, 22)
            appsHeader.frame(height: 42)
            if Self.hasSearch(model) { searchField.frame(height: 44) }
            appList.frame(height: Self.rowsHeight(model: model, maximum: maxRowsHeight))
            footer.frame(height: 44)
        }
        .frame(width: width).background(surface.background).tint(MixerStyle.accent).preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if surface == .popover {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(MixerStyle.accent).frame(width: 28)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Levels").font(.system(size: surface == .island ? 18 : 17, weight: .semibold))
                Text("Per-app volume").font(.system(size: 11)).foregroundStyle(MixerStyle.secondary)
            }
            Spacer()
            Menu {
                Picker("Display Mode", selection: $model.presentationMode) {
                    ForEach(MixerPresentation.allCases) { mode in Text(mode.name).tag(mode) }
                }.pickerStyle(.inline)
                Divider()
                Button("Open Mixer Window", systemImage: "macwindow", action: openWindow)
                Toggle("Show Inactive Apps", isOn: $model.showInactive)
                Button("Reset All App Volumes", systemImage: "arrow.counterclockwise", action: model.resetAll)
                if model.access == .ready {
                    Button("Pause App Mixing", systemImage: "pause.circle", action: model.suspendMixing)
                    Button("Recheck Audio Access", action: model.checkAccess)
                }
                Divider()
                Button("Levels Setup Guide…", systemImage: "questionmark.circle", action: model.openSetupGuide)
                Button("Audio Privacy Settings…", action: model.openPrivacySettings)
                Divider()
                Button("Quit Levels", action: quit).keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .medium))
                    .foregroundStyle(MixerStyle.secondary).frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Mixer options").help("Mixer options and display mode")
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: surface == .island ? "chevron.up" : "xmark").font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(MixerIconButtonStyle())
                .accessibilityLabel(surface == .island ? "Collapse mixer" : "Close mixer")
                .help(surface == .island ? "Collapse to the notch · Escape" : "Close popover · Escape")
            }
        }.padding(.horizontal, 22)
    }

    private var outputSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("Output").font(.system(size: 12, weight: .medium)).foregroundStyle(MixerStyle.secondary)
                Spacer(minLength: 8)
                Menu {
                    ForEach(model.devices) { device in
                        Button { model.selectOutput(device.id) } label: {
                            if device.id == model.outputID { Label(device.name, systemImage: "checkmark") }
                            else { Text(device.name) }
                        }
                    }
                } label: {
                    Text(model.output?.name ?? "No output")
                        .font(.system(size: 12, weight: .medium)).lineLimit(1)
                        .truncationMode(.middle)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .padding(.trailing, 20)
                .overlay(alignment: .trailing) {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MixerStyle.secondary).allowsHitTesting(false)
                }
                .fixedSize(horizontal: false, vertical: true).accessibilityLabel("Output device")
            }
            if let volume = model.masterVolume {
                HStack(spacing: 10) {
                    Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12)).foregroundStyle(MixerStyle.secondary).frame(width: 28)
                    Slider(value: Binding(get: { model.masterVolume ?? 0 }, set: model.setMaster), in: 0...1)
                        .accessibilityLabel("System volume")
                        .accessibilityValue("\(Int((volume * 100).rounded())) percent")
                    Text("\(Int((volume * 100).rounded()))%")
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                        .foregroundStyle(MixerStyle.secondary).frame(width: 40, alignment: .trailing)
                }
            } else {
                Text("Use this output’s hardware volume controls.").font(.system(size: 12))
                    .foregroundStyle(MixerStyle.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.horizontal, 22)
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.access == .unavailable ? "Audio access needs attention" : "Enable app volume control", systemImage: "waveform")
                .font(.system(size: 13, weight: .semibold))
            Text(model.access == .unavailable
                 ? model.message ?? "Allow System Audio Recording, then check again."
                 : "Allow System Audio Recording to mix each app. Audio stays on your Mac and is never saved.")
                .font(.system(size: 12)).foregroundStyle(MixerStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if model.access == .checking {
                    ProgressView().controlSize(.small)
                    Text("Checking audio access…").font(.system(size: 12)).foregroundStyle(MixerStyle.secondary)
                } else {
                    Button(model.access == .unavailable ? "Check Again" : "Enable App Volume", action: model.checkAccess)
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    if model.access == .unavailable {
                        Button("Open Settings", action: model.openPrivacySettings).buttonStyle(.bordered).controlSize(.small)
                    }
                }
                Spacer()
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 22)
    }

    private var appsHeader: some View {
        HStack {
            Text("Apps").font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("\(model.visibleApps.count)").font(.system(size: 12)).monospacedDigit().foregroundStyle(MixerStyle.secondary)
        }.padding(.horizontal, 22)
    }
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(MixerStyle.secondary)
            TextField("Find an app", text: $model.search).textFieldStyle(.plain).font(.system(size: 12))
        }.padding(9).background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 22).padding(.bottom, 8)
    }
    private var appList: some View {
        Group {
            if model.visibleApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(MixerStyle.secondary)
                    Text(model.search.isEmpty ? "Play something to get started" : "No matching apps")
                        .font(.system(size: 13, weight: .medium))
                    Text(model.search.isEmpty ? "Apps appear when they use audio." : "Try a different app name.")
                        .font(.system(size: 12)).foregroundStyle(MixerStyle.secondary)
                    if model.search.isEmpty && !model.apps.isEmpty {
                        Button("Show Inactive Apps") { model.showInactive = true }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(MixerStyle.accent)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.visibleApps) { app in AppVolumeRow(app: app, model: model, surface: surface) }
                    }
                }.scrollIndicators(.automatic)
            }
        }
    }
    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(model.access == .ready ? MixerStyle.accent : MixerStyle.secondary).frame(width: 5, height: 5)
            Text(model.access == .ready ? "Mixing on this Mac" : "App mixing is off")
                .font(.system(size: 11)).foregroundStyle(MixerStyle.secondary)
            Spacer()
            Button("Reset All", action: model.resetAll).buttonStyle(.plain)
                .font(.system(size: 11)).foregroundStyle(MixerStyle.secondary)
                .help("Restore all applications to 100% and unmute them")
        }.padding(.horizontal, 22)
    }
}

private struct AppVolumeRow: View {
    let app: AudioApp
    @ObservedObject var model: MixerModel
    var surface: MixerSurface
    private var value: VolumeSetting { model.setting(app.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Group {
                    if let icon = app.icon { Image(nsImage: icon).resizable().interpolation(.high) }
                    else { Image(systemName: "app.fill").resizable().foregroundStyle(MixerStyle.secondary) }
                }.frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if let error = model.appErrors[app.id] {
                        Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2).help(error)
                    } else {
                        Text(model.access != .ready && value.needsProcessing ? "Saved level · enable audio access to apply" : value.muted ? "Muted" : app.isPlaying ? "Audio active" : "Idle")
                            .font(.system(size: 11))
                            .foregroundStyle(surface == .popover && app.isPlaying && !value.muted ? MixerStyle.accent : MixerStyle.secondary)
                    }
                }
                Spacer(minLength: 4)
                if model.appErrors[app.id] != nil {
                    Button { model.retry(app.id) } label: { Image(systemName: "arrow.clockwise").frame(width: 28, height: 28) }
                        .buttonStyle(MixerIconButtonStyle()).help("Retry audio for \(app.name)")
                        .accessibilityLabel("Retry \(app.name)")
                }
            }
            HStack(spacing: 10) {
                Button { model.toggleMute(app.id) } label: {
                    Image(systemName: value.muted || value.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12)).foregroundStyle(value.muted ? MixerStyle.accent : MixerStyle.secondary)
                        .frame(width: 28, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(MixerIconButtonStyle())
                .accessibilityLabel("\(value.muted ? "Unmute" : "Mute") \(app.name)")
                .help("\(value.muted ? "Unmute" : "Mute") \(app.name)")
                Slider(value: Binding(get: { value.volume }, set: { model.setVolume(app.id, $0) }), in: 0...1)
                    .accessibilityLabel("\(app.name) volume")
                    .accessibilityValue("\(Int((value.volume * 100).rounded())) percent").opacity(value.muted ? 0.5 : 1)
                Text(value.muted ? "Muted" : "\(Int((value.volume * 100).rounded()))%")
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(value.muted ? MixerStyle.secondary : .white).frame(width: 40, alignment: .trailing)
            }.disabled(model.access != .ready)
        }
        .padding(.horizontal, 22).frame(height: model.appErrors[app.id] == nil ? 88 : 106)
        .contextMenu { Button("Reset \(app.name) to 100%") { model.reset(app.id) } }
    }
}

private struct MixerIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(MixerStyle.secondary)
            .background(Color.white.opacity(configuration.isPressed ? 0.14 : 0), in: RoundedRectangle(cornerRadius: 6))
    }
}
