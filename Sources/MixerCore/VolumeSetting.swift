import Foundation

public struct VolumeSetting: Codable, Equatable, Sendable {
    public var volume: Double
    public var muted: Bool

    public init(volume: Double = 1, muted: Bool = false) {
        self.volume = volume.isFinite ? min(1, max(0, volume)) : 1
        self.muted = muted
    }

    public var gain: Float { muted ? 0 : Float(volume.isFinite ? min(1, max(0, volume)) : 1) }
    public var needsProcessing: Bool { muted || gain < 0.9999 }
}

public enum AppIdentity {
    // Longest bundle prefix wins: e.g. a Chrome helper belongs to Chrome,
    // while com.example.Editor.Pro remains separate from com.example.Editor.
    public static func owner(of bundleID: String, candidates: [String]) -> String? {
        candidates.filter { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
            .max { $0.count < $1.count }
    }
}
