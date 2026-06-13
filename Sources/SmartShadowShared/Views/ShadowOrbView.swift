import SwiftUI

public struct ShadowOrbView: View {
    public var state: VoiceEntryState
    public var size: CGFloat
    @State private var pulse = false

    public init(state: VoiceEntryState, size: CGFloat) {
        self.state = state
        self.size = size
    }

    public var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle()
                    .stroke(ShadowColors.cyan.opacity(state.pulseOpacity / Double(index + 1)), lineWidth: 1)
                    .frame(width: size + CGFloat(index * 38), height: size + CGFloat(index * 38))
                    .scaleEffect(pulse ? 1.08 : 0.92)
            }

            Circle()
                .trim(from: 0.10, to: state.showsProgressRing ? 0.82 : 0.30)
                .stroke(state.ringColor.opacity(0.82), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: size + 12, height: size + 12)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.88),
                            ShadowColors.cyan,
                            ShadowColors.violet,
                            ShadowColors.violetDeep,
                            .black.opacity(0.96)
                        ],
                        center: .center,
                        startRadius: 5,
                        endRadius: size * 0.62
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(state.ringColor.opacity(0.72), lineWidth: 1.2)
                        .blur(radius: 1.2)
                )
                .shadow(color: state.ringColor.opacity(0.50), radius: 26, x: 0, y: 0)
                .scaleEffect(state.orbScale)
        }
        .animation(.easeInOut(duration: 0.7), value: state)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
