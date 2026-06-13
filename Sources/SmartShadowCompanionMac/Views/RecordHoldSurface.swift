import SmartShadowShared
import SwiftUI

struct RecordHoldSurface: View {
    @ObservedObject var model: MacCompanionModel
    var orbSize: CGFloat
    var showWave: Bool = true
    @State private var isPressing = false

    var body: some View {
        VStack(spacing: 18) {
            ShadowOrbView(state: model.state, size: orbSize)
                .scaleEffect(isPressing ? 1.03 : 1.0)
                .gesture(recordGesture)
                .accessibilityIdentifier("shadowOrb")
                .accessibilityLabel("Press and hold to record")

            VStack(spacing: 5) {
                Text(model.state.statusText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(ShadowColors.mutedText)
                    .lineLimit(1)
            }

            if showWave {
                VoiceWaveView(active: model.state == .recording || model.state == .uploading || model.state == .thinking || model.state == .executing)
                    .frame(height: 34)
                    .padding(.horizontal, 28)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.state)
    }

    private var statusDetail: String {
        if let error = model.errorMessage, model.state == .failed {
            return error
        }
        switch model.state {
        case .idle:
            return "Use Shadow Command for local voice processing"
        case .recording:
            return "Release to stop. GitHub audio upload is disabled"
        case .uploading:
            return "Legacy upload path is disabled"
        case .uploaded:
            return "Final text was submitted to GitHub"
        case .failed:
            return "Use local processing, then confirm the GitHub write"
        case .thinking:
            return "Building a repo-aware suggestion"
        case .executing:
            return "Running the confirmed GitHub operation"
        case .done:
            return "Operation completed"
        case .confirm:
            return "Review before GitHub write"
        case .error:
            return "Check GitHub auth or network"
        }
    }

    private var recordGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isPressing else { return }
                isPressing = true
                Task { await model.startPressRecording() }
            }
            .onEnded { _ in
                guard isPressing else { return }
                isPressing = false
                model.finishPressRecording()
            }
    }
}
