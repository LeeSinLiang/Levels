import Foundation
import CoreGraphics

/// Placement is driven by the screen's reported camera housing, including
/// displays with negative origins and monitors without a housing.
public struct IslandGeometry: Sendable {
    public let screen: CGRect
    public let visibleScreen: CGRect
    public let notch: CGRect?

    public init(screen: CGRect, visibleScreen: CGRect, topInset: CGFloat, leftArea: CGRect?, rightArea: CGRect?) {
        self.screen = screen
        self.visibleScreen = visibleScreen
        if topInset > 0, let leftArea, let rightArea, rightArea.minX > leftArea.maxX {
            notch = CGRect(x: leftArea.maxX, y: screen.maxY - topInset, width: rightArea.minX - leftArea.maxX, height: topInset)
        } else { notch = nil }
    }

    public var hasNotch: Bool { notch != nil }
    public var capHeight: CGFloat { notch?.height ?? 34 }
    public var notchWidth: CGFloat { notch?.width ?? 0 }
    public var availableHeight: CGFloat { max(80, anchorTop - visibleScreen.minY - 12) }
    private var anchorTop: CGFloat { hasNotch ? screen.maxY : min(screen.maxY, visibleScreen.maxY) - 12 }

    public func frame(expanded: Bool, bodyHeight: CGFloat) -> CGRect {
        let width = min(expanded ? 430 : hasNotch ? notchWidth + 88 : 148, screen.width - 24)
        let height = min(expanded ? capHeight + bodyHeight : hasNotch ? capHeight + 8 : 36, availableHeight)
        let center = notch?.midX ?? screen.midX
        let x = min(screen.maxX - width - 12, max(screen.minX + 12, center - width / 2))
        return CGRect(x: x, y: anchorTop - height, width: width, height: height)
    }
}
