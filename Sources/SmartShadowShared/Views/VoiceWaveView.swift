import SwiftUI

public struct VoiceWaveView: View {
    public var active: Bool

    public init(active: Bool) {
        self.active = active
    }

    public var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let midY = size.height / 2
                let time = timeline.date.timeIntervalSinceReferenceDate
                var path = Path()
                let count = 42

                for index in 0..<count {
                    let x = size.width * CGFloat(index) / CGFloat(count - 1)
                    let wave = sin(Double(index) * 0.72 + time * (active ? 5.4 : 1.3))
                    let height = CGFloat(abs(wave)) * (active ? 20 : 7) + 2
                    path.move(to: CGPoint(x: x, y: midY - height / 2))
                    path.addLine(to: CGPoint(x: x, y: midY + height / 2))
                }

                context.stroke(path, with: .color(.white.opacity(active ? 0.80 : 0.32)), lineWidth: 1.2)
            }
        }
    }
}
