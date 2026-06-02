import AppKit
import SmartShadowMenuCore
import SwiftUI

@main
struct SmartShadowMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = StatusPanelStore()

    var body: some Scene {
        MenuBarExtra {
            StatusPanelView(store: store)
                .frame(width: 420)
                .task {
                    await store.refresh()
                }
        } label: {
            Label("Smart Shadow", systemImage: store.snapshot.summary.systemImage)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

