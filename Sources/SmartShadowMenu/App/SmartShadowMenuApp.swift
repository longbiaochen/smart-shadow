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
                .frame(width: 460)
                .task {
                    await store.refresh()
                }
        } label: {
            MenuBarStatusIcon(summary: store.snapshot.summary)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct MenuBarStatusIcon: View {
    let summary: ServiceSummary

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "moon.stars.circle.fill")
                .symbolRenderingMode(.hierarchical)
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
                .offset(x: 1, y: 1)
        }
        .accessibilityLabel("智能影子 \(summary.title)")
    }

    private var statusColor: Color {
        switch summary {
        case .running: .green
        case .attention: .orange
        case .stopped: .secondary
        case .unknown: .red
        }
    }
}
