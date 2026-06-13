import SmartShadowShared
import SwiftUI

struct VoicePanelView: View {
    @ObservedObject var model: MacCompanionModel

    var body: some View {
        ZStack {
            ShadowBackground()
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                Spacer(minLength: 10)

                RecordHoldSurface(model: model, orbSize: 124)

                Spacer(minLength: 8)

                RecentDeliveryList(deliveries: Array(model.deliveryHistory.prefix(4)))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hello, \(model.userLogin ?? "Longbiao")")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("按住，说给影子听")
                    .font(.caption)
                    .foregroundStyle(ShadowColors.mutedText)
            }

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.72))
            .help("Open settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.54))
            .help("Quit SmartShadow")
        }
    }
}

private struct RecentDeliveryList: View {
    let deliveries: [VoicePacketDelivery]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent delivery status")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))

            if deliveries.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                    Text("No packets yet")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.42))
                .padding(10)
                .background(ShadowColors.panel, in: RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(deliveries) { delivery in
                    HStack(spacing: 8) {
                        Image(systemName: delivery.status == .uploaded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(delivery.status == .uploaded ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(delivery.status.title)
                                .font(.caption.weight(.medium))
                            Text(delivery.repositoryPath)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.42))
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(delivery.displayTime)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(9)
                    .background(ShadowColors.panel, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}
