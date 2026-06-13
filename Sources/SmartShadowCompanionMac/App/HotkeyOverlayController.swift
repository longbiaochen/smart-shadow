import AppKit
import SwiftUI

@MainActor
final class HotkeyOverlayController {
    private let panel: NSPanel

    init(model: MacCompanionModel) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: HotkeyOverlayView(model: model).frame(width: 480, height: 220))
        center()
    }

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        center()
        panel.orderFrontRegardless()
    }

    private func center() {
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }
        let frame = panel.frame
        let origin = NSPoint(
            x: screenFrame.midX - frame.width / 2,
            y: screenFrame.midY - frame.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}
