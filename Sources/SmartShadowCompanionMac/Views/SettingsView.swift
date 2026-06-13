import SmartShadowShared
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: MacCompanionModel

    var body: some View {
        Form {
            Section("GitHub") {
                LabeledContent("Account") {
                    Text(model.accountTitle)
                        .foregroundStyle(.secondary)
                }
                TextField("Owner", text: $model.settings.owner)
                TextField("Target repo", text: $model.settings.repo)
                TextField("Inbox path", text: $model.settings.inboxPath)
                TextField("OAuth Client ID", text: $model.oauthClientID)
            }

            Section("Entry") {
                LabeledContent("Hotkey") {
                    HStack(spacing: 6) {
                        KeyCap("⌥")
                        Text("+")
                            .foregroundStyle(.secondary)
                        KeyCap("Space")
                    }
                }

                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            Section {
                HStack {
                    Button("Save") {
                        model.saveSettings()
                    }
                    Button(model.isAuthenticated ? "Reconnect GitHub" : "Connect GitHub") {
                        NotificationCenter.default.post(name: .smartShadowShowLogin, object: nil)
                    }
                    Button("Logout", role: .destructive) {
                        model.logout()
                    }
                    Spacer()
                }
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }
}

private struct KeyCap: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(minWidth: 38, minHeight: 28)
            .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}
