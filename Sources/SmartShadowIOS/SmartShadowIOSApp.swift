import SwiftUI

@main
struct SmartShadowIOSApp: App {
    @StateObject private var session = ShadowSession()

    var body: some Scene {
        WindowGroup {
            SmartShadowRootView()
                .environmentObject(session)
                .onOpenURL { url in
                    session.applyFollowUpURL(url)
                }
        }
    }
}
