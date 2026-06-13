import SmartShadowShared
import SwiftUI

struct HotkeyOverlayView: View {
    @ObservedObject var model: MacCompanionModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [ShadowColors.baseMid.opacity(0.88), ShadowColors.baseBottom.opacity(0.82)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(ShadowColors.border))

            HStack(spacing: 24) {
                RecordHoldSurface(model: model, orbSize: 104, showWave: false)
                    .frame(width: 210)

                VStack(alignment: .leading, spacing: 10) {
                    Text("SmartShadow")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("语音本地处理，确认后写 GitHub")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(ShadowColors.mutedText)
                    Text("ESC 退出")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.38))
                        .padding(.top, 16)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
    }
}
