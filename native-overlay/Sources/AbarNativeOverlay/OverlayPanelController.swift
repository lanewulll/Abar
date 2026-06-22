import AbarOverlayCore
import AppKit
import SwiftUI

@MainActor
final class OverlayPanelController {
    private var panel: AbarOverlayPanel?
    private lazy var model = AbarOverlayModel { [weak self] in
        self?.showCompletionGlow()
    }
    private let completionGlowController = CompletionGlowController()
    private var collapseWorkItem: DispatchWorkItem?

    func show() {
        model.start()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        collapse(animated: false)
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func refresh() {
        model.refresh()
    }

    private func makePanel() -> AbarOverlayPanel {
        let screen = targetScreen()
        let frame = panelFrame(on: screen)
        let panel = AbarOverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        let contentView = HoverTrackingHostingView(rootView: AbarOverlayView(model: model))
        contentView.onMouseEntered = { [weak self] in
            self?.expand()
        }
        contentView.onMouseExited = { [weak self] in
            self?.scheduleCollapse()
        }
        panel.contentView = contentView
        return panel
    }

    private func position(_ panel: NSPanel) {
        panel.setFrame(panelFrame(on: targetScreen()), display: true)
    }

    private func expand() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        guard let panel else { return }
        model.setExpanded(true)
        setPanel(panel, frame: panelFrame(on: targetScreen()), animated: true)
    }

    private func scheduleCollapse() {
        collapseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.collapse(animated: true)
        }
        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func collapse(animated: Bool) {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        guard let panel else { return }
        model.setExpanded(false)
        setPanel(panel, frame: collapsedPanelFrame(on: targetScreen()), animated: animated)
    }

    private func setPanel(_ panel: NSPanel, frame: NSRect, animated: Bool) {
        if animated {
            panel.animator().setFrame(frame, display: true)
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func showCompletionGlow() {
        completionGlowController.show(on: targetScreen())
    }

    private func panelFrame(on screen: NSScreen) -> NSRect {
        let snapshot = OverlayScreenSnapshot(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top
        )
        return OverlayGeometry.panelFrame(on: snapshot)
    }

    private func collapsedPanelFrame(on screen: NSScreen) -> NSRect {
        let snapshot = OverlayScreenSnapshot(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top
        )
        return OverlayGeometry.collapsedPanelFrame(on: snapshot)
    }

    private func targetScreen() -> NSScreen {
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }
}

final class AbarOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class HoverTrackingHostingView<Content: View>: NSHostingView<Content> {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configure()
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }
}

@MainActor
final class CompletionGlowController {
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(on screen: NSScreen) {
        hideWorkItem?.cancel()
        let panel = self.panel ?? makePanel(on: screen)
        self.panel = panel
        panel.setFrame(glowFrame(on: screen), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let workItem = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
            }
        }
    }

    private func makePanel(on screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: glowFrame(on: screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .mainMenu + 4
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: CompletionGlowView())
        return panel
    }

    private func glowFrame(on screen: NSScreen) -> NSRect {
        let snapshot = OverlayScreenSnapshot(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top
        )
        return OverlayGeometry.completionGlowFrame(on: snapshot)
    }
}

private struct CompletionGlowView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(Color(red: 0.10, green: 0.78, blue: 0.46).opacity(0.95), lineWidth: 2)
            .shadow(color: Color(red: 0.10, green: 0.78, blue: 0.46).opacity(0.95), radius: 16)
            .shadow(color: Color(red: 0.10, green: 0.78, blue: 0.46).opacity(0.45), radius: 28)
            .padding(6)
            .background(Color.clear)
    }
}
