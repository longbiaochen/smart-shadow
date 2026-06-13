import AppKit
import SmartShadowGitHubAPI
import SmartShadowShared
import SwiftUI

struct LoginWindowView: View {
    @ObservedObject var model: MacCompanionModel

    var body: some View {
        ZStack {
            ShadowBackground()
            VStack(spacing: 24) {
                Spacer(minLength: 16)

                ShadowOrbView(state: .idle, size: 92)

                VStack(spacing: 8) {
                    Text("Welcome to\nSmartShadow")
                        .font(.system(size: 27, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Text("登录后开启语音投递")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(ShadowColors.mutedText)
                }

                VStack(spacing: 12) {
                    if model.oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        TextField("GitHub OAuth Client ID", text: $model.oauthClientID)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(ShadowColors.panel, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ShadowColors.border))
                    }

                    Button {
                        Task { await model.beginLogin() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                            Text(model.isLoggingIn ? "Waiting for GitHub..." : "Continue with GitHub")
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isLoggingIn || model.oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 42)

                if let deviceCode = model.deviceCode {
                    DeviceCodeView(deviceCode: deviceCode)
                        .padding(.horizontal, 38)
                }

                if let error = model.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)
                }

                Spacer()

                Text("只上传 voice packet；不创建 issue 或评论")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.bottom, 22)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct DeviceCodeView: View {
    let deviceCode: GitHubOAuthDeviceCodeResponse

    var body: some View {
        VStack(spacing: 8) {
            Text("GitHub device code")
                .font(.caption)
                .foregroundStyle(ShadowColors.mutedText)
            Text(deviceCode.userCode)
                .font(.system(size: 25, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Text("Code copied. Confirm it in the browser.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(ShadowColors.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ShadowColors.violet.opacity(0.24)))
    }
}
