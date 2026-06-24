import AbarOverlayCore
import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var onToggle: (() -> Void)?
    private var onOpenStatusCenter: (() -> Void)?
    private var onRefresh: (() -> Void)?
    private var onQuit: (() -> Void)?
    private var state: AbarStatusSignal = .idle
    private var animationTimer: Timer?
    private var pulsePhase = false

    func start(
        onToggle: @escaping () -> Void,
        onOpenStatusCenter: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onToggle = onToggle
        self.onOpenStatusCenter = onOpenStatusCenter
        self.onRefresh = onRefresh
        self.onQuit = onQuit
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(statusButtonPressed(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Abar"
        render()
    }

    func update(state: AbarStatusSignal) {
        self.state = state
        updateAnimationTimer()
        render()
    }

    func showCompletionPulse() {
        render()
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
        menu.addItem(NSMenuItem(title: StatusItemMenuDefinition.statusCenterTitle, action: #selector(statusCenterPressed), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: StatusItemMenuDefinition.refreshTitle, action: #selector(refreshPressed), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: StatusItemMenuDefinition.quitTitle, action: #selector(quitPressed), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    @objc private func statusCenterPressed() {
        onOpenStatusCenter?()
    }

    @objc private func refreshPressed() {
        onRefresh?()
    }

    @objc private func quitPressed() {
        onQuit?()
    }

    private func render() {
        render(appearance: AbarStatusIconAppearance.resolve(state: state, pulsePhase: pulsePhase))
    }

    private func render(appearance: AbarStatusIconAppearance) {
        guard let button = item.button else { return }
        button.image = StatusCIconImage.make(color: appearance.color, glow: appearance.glow, alpha: appearance.alpha)
        button.image?.isTemplate = appearance.isTemplate
        button.imagePosition = .imageOnly
    }

    private func updateAnimationTimer() {
        guard state == .running else {
            stopAnimationTimer()
            return
        }
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.72, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .running else { return }
                self.pulsePhase.toggle()
                self.render()
            }
        }
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
        pulsePhase = false
    }
}

enum AbarStatusIconTone: Equatable {
    case system
    case green
    case red
}

struct AbarStatusIconAppearance: Equatable {
    let tone: AbarStatusIconTone
    let glow: Bool
    let alpha: CGFloat
    let isTemplate: Bool

    static func resolve(state: AbarStatusSignal, pulsePhase: Bool) -> AbarStatusIconAppearance {
        switch state {
        case .idle:
            return AbarStatusIconAppearance(tone: .system, glow: false, alpha: 1.0, isTemplate: true)
        case .running:
            return AbarStatusIconAppearance(tone: .green, glow: true, alpha: pulsePhase ? 1.0 : 0.70, isTemplate: false)
        case .interrupted:
            return AbarStatusIconAppearance(tone: .red, glow: false, alpha: 1.0, isTemplate: false)
        }
    }

    fileprivate var color: NSColor {
        switch tone {
        case .system:
            return .labelColor
        case .green:
            return NSColor(calibratedRed: 0.48, green: 0.86, blue: 0.58, alpha: 1)
        case .red:
            return NSColor(calibratedRed: 1.00, green: 0.28, blue: 0.24, alpha: 1)
        }
    }
}

private enum StatusCIconImage {
    static func make(color: NSColor, glow: Bool, alpha: CGFloat) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        if glow {
            color.withAlphaComponent(0.12 * alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: 1, y: 0, width: 20, height: 18)).fill()
            color.withAlphaComponent(0.18 * alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: 4, y: 2, width: 14, height: 14)).fill()
        }

        let text = "C" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .black),
            .foregroundColor: color.withAlphaComponent(alpha)
        ]
        let textSize = text.size(withAttributes: attributes)
        let origin = NSPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2 - 1
        )
        text.draw(at: origin, withAttributes: attributes)
        image.unlockFocus()
        return image
    }
}
