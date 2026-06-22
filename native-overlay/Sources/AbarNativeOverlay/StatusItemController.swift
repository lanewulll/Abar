import AbarOverlayCore
import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var onToggle: (() -> Void)?
    private var onQuit: (() -> Void)?
    private var state: AbarActivityState = .idle
    private var pulseWorkItem: DispatchWorkItem?
    private var isShowingCompletionPulse = false

    func start(onToggle: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onQuit = onQuit
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(statusButtonPressed(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Abar"
        render()
    }

    func update(state: AbarActivityState) {
        self.state = state
        guard !isShowingCompletionPulse else { return }
        render()
    }

    func showCompletionPulse() {
        pulseWorkItem?.cancel()
        isShowingCompletionPulse = true
        render(color: StatusPalette.completed, glow: true)

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.isShowingCompletionPulse = false
                self?.render()
            }
        }
        pulseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    @objc private func statusButtonPressed(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(from: sender)
            return
        }
        onToggle?()
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Abar", action: #selector(quitPressed), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    @objc private func quitPressed() {
        onQuit?()
    }

    private func render() {
        switch state {
        case .idle:
            render(color: StatusPalette.idle, glow: false)
        case .working:
            render(color: StatusPalette.working, glow: false)
        }
    }

    private func render(color: NSColor, glow: Bool) {
        guard let button = item.button else { return }
        button.image = StatusDotImage.make(color: color, glow: glow)
        button.image?.isTemplate = false
        button.imagePosition = .imageOnly
    }
}

private enum StatusPalette {
    static let idle = NSColor(calibratedRed: 0.48, green: 0.86, blue: 0.58, alpha: 1)
    static let working = NSColor(calibratedRed: 0.98, green: 0.76, blue: 0.25, alpha: 1)
    static let completed = NSColor(calibratedRed: 0.05, green: 0.92, blue: 0.45, alpha: 1)
}

private enum StatusDotImage {
    static func make(color: NSColor, glow: Bool) -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        if glow {
            color.withAlphaComponent(0.20).setFill()
            NSBezierPath(ovalIn: NSRect(x: 1, y: 0, width: 18, height: 18)).fill()
            color.withAlphaComponent(0.32).setFill()
            NSBezierPath(ovalIn: NSRect(x: 3, y: 2, width: 14, height: 14)).fill()
        }

        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 5, y: 4, width: 10, height: 10)).fill()
        image.unlockFocus()
        return image
    }
}
