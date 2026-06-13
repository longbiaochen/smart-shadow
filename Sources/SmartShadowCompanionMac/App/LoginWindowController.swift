import AppKit
import SwiftUI

@MainActor
final class LoginWindowController {
    private static var shared: LoginWindowController?
    private let window: NSWindow

    static func showShared(model: MacCompanionModel) {
        if shared == nil {
            shared = LoginWindowController(model: model)
        }
        shared?.show()
    }

    static func closeShared() {
        shared?.close()
    }

    init(model: MacCompanionModel) {
        let content = LoginWindowView(model: model)
            .frame(width: 420, height: 520)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "SmartShadow Login"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.center()
    }

    func show() {
        window.center()
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window.close()
    }
}
