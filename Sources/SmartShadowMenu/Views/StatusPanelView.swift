import AppKit
import SmartShadowMenuCore
import SwiftUI

struct StatusPanelView: View {
    @ObservedObject var store: StatusPanelStore

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    StatusHero(snapshot: store.snapshot, isWorking: store.isWorking)

                    if let error = store.snapshot.errorMessage {
                        ErrorBanner(message: error)
                    }

                    SummaryGrid(snapshot: store.snapshot)
                    AttentionListView(items: store.snapshot.serviceStatus?.attention ?? [])
                    SourceOverview(status: store.snapshot.serviceStatus)
                    RecentItems(items: Array((store.snapshot.healthStatus?.recent ?? []).prefix(5)))
                }
                .padding(16)
            }
            .frame(maxHeight: 640)

            Divider()
            ActionBar(store: store)
                .padding(12)
        }
    }
}

private struct StatusHero: View {
    let snapshot: MenuSnapshot
    let isWorking: Bool

    var body: some View {
        HStack(spacing: 14) {
            SmartShadowMark(summary: snapshot.summary)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("智能影子")
                        .font(.title3.weight(.semibold))
                    StatusCapsule(summary: snapshot.summary)
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("刷新 \(snapshot.refreshedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var subtitle: String {
        guard let status = snapshot.serviceStatus else {
            return "无法连接本地控制面"
        }
        let service = status.launchd.loaded ? "后台服务已加载" : "后台服务未加载"
        return "\(service) · \(status.pollSeconds)s 轮询"
    }
}

private struct SmartShadowMark: View {
    let summary: ServiceSummary

    var body: some View {
        ZStack {
            Circle()
                .fill(.primary.opacity(0.08))
            Circle()
                .strokeBorder(statusColor.opacity(0.45), lineWidth: 1)
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(statusColor)
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .offset(x: 18, y: 18)
        }
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

private struct StatusCapsule: View {
    let summary: ServiceSummary

    var body: some View {
        Text(summary.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch summary {
        case .running: .green
        case .attention: .orange
        case .stopped: .secondary
        case .unknown: .red
        }
    }
}

private struct SummaryGrid: View {
    let snapshot: MenuSnapshot

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            MetricTile(
                title: "最近运行",
                value: runValue,
                detail: runDetail,
                systemImage: "clock.arrow.circlepath"
            )
            MetricTile(
                title: "处理 / 错误",
                value: processedValue,
                detail: errorDetail,
                systemImage: "checklist.checked"
            )
            MetricTile(
                title: "Calendar",
                value: snapshot.serviceStatus?.eventKit.calendar ?? "未知",
                detail: "EventKit",
                systemImage: "calendar"
            )
            MetricTile(
                title: "Reminders",
                value: snapshot.serviceStatus?.eventKit.reminders ?? "未知",
                detail: "EventKit",
                systemImage: "checklist"
            )
        }
    }

    private var runValue: String {
        guard let report = snapshot.serviceStatus?.lastRunReport else { return "无报告" }
        return report.fresh == true ? "新鲜" : "过期"
    }

    private var runDetail: String {
        SmartShadowFormatters.relativeAge(seconds: snapshot.serviceStatus?.lastRunReport?.ageSeconds)
    }

    private var processedValue: String {
        let report = snapshot.serviceStatus?.lastRunReport
        return "\(report?.processedCount ?? 0) / \(report?.errorCount ?? 0)"
    }

    private var errorDetail: String {
        SmartShadowFormatters.shortTimestamp(snapshot.serviceStatus?.lastRunReport?.timestamp)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(minHeight: 72, alignment: .topLeading)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SourceOverview: View {
    let status: ServiceStatus?

    var body: some View {
        SectionBlock(title: "来源") {
            if let status {
                VStack(spacing: 6) {
                    ForEach(status.sourceDoctor.sources) { source in
                        SourceRow(source: source)
                    }
                }
            } else {
                Text("无法读取来源状态")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SourceRow: View {
    let source: SourceStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: source.readyToEnable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(source.readyToEnable ? .green : .orange)
                .frame(width: 16)
            Text(source.name)
                .lineLimit(1)
            Spacer()
            Text(source.enabled ? "已启用" : "未启用")
                .foregroundStyle(.secondary)
            Text(source.readyToEnable ? "ready" : source.blockers.joined(separator: ", "))
                .foregroundStyle(source.readyToEnable ? Color.secondary.opacity(0.65) : Color.orange)
                .lineLimit(1)
        }
        .font(.caption)
    }
}

private struct RecentItems: View {
    let items: [RecentItem]

    var body: some View {
        SectionBlock(title: "最近事项") {
            if items.isEmpty {
                Label("暂无最近事项", systemImage: "tray")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Text([item.domain, item.risk, item.status].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct ActionBar: View {
    @ObservedObject var store: StatusPanelStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = store.lastActionMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help("刷新状态")

                Button {
                    Task { await store.startService() }
                } label: {
                    Label("启动", systemImage: "play.fill")
                }
                .disabled(store.isWorking)
                .help("启动后台服务")

                Button {
                    Task { await store.stopService() }
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .disabled(store.isWorking)
                .help("停止后台服务")

                Button {
                    Task { await store.writeReport() }
                } label: {
                    Label("报告", systemImage: "doc.text")
                }
                .disabled(store.isWorking)
                .help("生成用户报告")

                Spacer()

                Menu {
                    Button("打开项目") { store.openProject() }
                    Button("打开日志") { store.openLogs() }
                    Divider()
                    Button("退出") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help("更多操作")
            }
        }
        .buttonStyle(.bordered)
        .labelStyle(.iconOnly)
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
