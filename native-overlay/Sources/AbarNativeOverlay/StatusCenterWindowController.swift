import AppKit
import SwiftUI

@MainActor
final class StatusCenterWindowController: NSWindowController {
    private let model: StatusCenterModel

    init(onRefreshOverlay: @escaping () -> Void) {
        model = StatusCenterModel(onRefreshOverlay: onRefreshOverlay)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Abar 状态中心"
        window.minSize = NSSize(width: 720, height: 540)
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: StatusCenterView(model: model))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        model.refresh()
    }
}
