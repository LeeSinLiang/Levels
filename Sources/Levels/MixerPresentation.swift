import Foundation

enum MixerPresentation: String, CaseIterable, Identifiable {
    case dynamicIsland
    case menuPopover

    var id: Self { self }
    var name: String {
        switch self {
        case .dynamicIsland: "Dynamic Island"
        case .menuPopover: "Menu Bar Popover"
        }
    }
}
