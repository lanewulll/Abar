import CoreGraphics

public struct OverlayScreenSnapshot: Equatable {
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let safeAreaTop: CGFloat

    public init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
    }
}

public struct OverlayGeometry {
    public static let preferredWidth: CGFloat = 500
    public static let preferredHeight: CGFloat = 228
    public static let collapsedWidth: CGFloat = 180
    public static let completionGlowWidth: CGFloat = 180
    public static let completionGlowHeight: CGFloat = 48
    public static let horizontalMargin: CGFloat = 16

    public static func panelFrame(on screen: OverlayScreenSnapshot) -> CGRect {
        let width = min(preferredWidth, max(240, screen.frame.width - (horizontalMargin * 2)))
        let height = preferredHeight
        return CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    public static func closedHeight(for screen: OverlayScreenSnapshot) -> CGFloat {
        if screen.safeAreaTop > 0 {
            return screen.safeAreaTop
        }

        let reservedTop = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        return reservedTop > 0 ? reservedTop : 24
    }

    public static func collapsedPanelFrame(on screen: OverlayScreenSnapshot) -> CGRect {
        let width = min(collapsedWidth, max(44, screen.frame.width - (horizontalMargin * 2)))
        let height = closedHeight(for: screen)
        return CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    public static func completionGlowFrame(on screen: OverlayScreenSnapshot) -> CGRect {
        let width = min(completionGlowWidth, max(80, screen.frame.width - (horizontalMargin * 2)))
        let height = completionGlowHeight
        return CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }
}
