import SwiftUI

public enum ShadowColors {
    public static let cyan = Color(red: 0.35, green: 0.90, blue: 0.98)
    public static let violet = Color(red: 0.49, green: 0.28, blue: 1.0)
    public static let violetDeep = Color(red: 0.18, green: 0.08, blue: 0.34)
    public static let baseTop = Color(red: 0.018, green: 0.026, blue: 0.046)
    public static let baseMid = Color(red: 0.026, green: 0.036, blue: 0.064)
    public static let baseBottom = Color(red: 0.008, green: 0.012, blue: 0.026)
    public static let panel = Color.white.opacity(0.060)
    public static let card = Color(red: 0.09, green: 0.12, blue: 0.20).opacity(0.78)
    public static let border = Color.white.opacity(0.085)
    public static let mutedText = Color.white.opacity(0.62)
}

public enum VoiceEntryState: Equatable {
    case idle
    case recording
    case uploading
    case uploaded
    case failed
    case thinking
    case executing
    case done
    case confirm
    case error

    public var statusText: String {
        switch self {
        case .idle: "按住，说给影子听"
        case .recording: "松开上传"
        case .uploading: "正在送达 GitHub"
        case .uploaded: "影子已收到"
        case .failed: "上传失败"
        case .thinking: "影子正在思考"
        case .executing: "正在执行"
        case .done: "已完成"
        case .confirm: "等待确认"
        case .error: "执行失败"
        }
    }

    public var orbScale: CGFloat {
        switch self {
        case .idle: 1.0
        case .recording: 1.14
        case .uploading: 0.88
        case .uploaded: 1.06
        case .failed: 0.94
        case .thinking: 1.04
        case .executing: 0.90
        case .done: 1.08
        case .confirm: 1.12
        case .error: 0.94
        }
    }

    public var pulseOpacity: Double {
        switch self {
        case .idle: 0.22
        case .recording: 0.48
        case .uploading: 0.16
        case .uploaded: 0.30
        case .failed: 0.20
        case .thinking: 0.28
        case .executing: 0.18
        case .done: 0.34
        case .confirm: 0.42
        case .error: 0.24
        }
    }

    public var ringColor: Color {
        switch self {
        case .idle, .recording, .thinking:
            ShadowColors.cyan
        case .uploading, .executing:
            ShadowColors.violet
        case .uploaded, .done:
            .green
        case .confirm:
            .orange
        case .failed, .error:
            .red
        }
    }

    public var showsProgressRing: Bool {
        switch self {
        case .uploading, .executing:
            true
        default:
            false
        }
    }
}

public struct ShadowBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [ShadowColors.baseTop, ShadowColors.baseMid, ShadowColors.baseBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadarGridView()
                .opacity(0.18)
            StarFieldView()
                .opacity(0.14)
        }
    }
}

private struct RadarGridView: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.72, y: size.height * 0.28)
            for radius in stride(from: 80.0, through: Double(max(size.width, size.height)) * 0.90, by: 92.0) {
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(ShadowColors.cyan.opacity(0.16)), lineWidth: 0.6)
            }
            for x in stride(from: 0.0, through: Double(size.width), by: 64.0) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.white.opacity(0.035)), lineWidth: 0.5)
            }
            for y in stride(from: 0.0, through: Double(size.height), by: 64.0) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.white.opacity(0.030)), lineWidth: 0.5)
            }
        }
    }
}

private struct StarFieldView: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<46 {
                let x = CGFloat((index * 73) % 997) / 997 * size.width
                let y = CGFloat((index * 149) % 991) / 991 * size.height
                let radius = CGFloat((index % 2) + 1) * 0.42
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                    with: .color(.white.opacity(index % 5 == 0 ? 0.36 : 0.12))
                )
            }
        }
    }
}
