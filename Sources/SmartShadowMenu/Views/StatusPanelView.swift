import AppKit
import SmartShadowMenuCore
import SwiftUI

struct StatusPanelView: View {
    @ObservedObject var store: StatusPanelStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let error = store.snapshot.errorMessage {
                ErrorBanner(message: error)
            }

            AttentionListView(items: store.snapshot.serviceStatus?.attention ?? [])

            runReportSection
            eventKitAndSourcesSection
            recentItemsSection
            actions
        }
        .padding(16)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: store.snapshot.summary.systemImage)
                .font(.system(size: 28))
                .foregroundStyle(summaryColor)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text("智能影子")
                    .font(.headline)
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("刷新: \(store.snapshot.refreshedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if store.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var headerSubtitle: String {
        guard let status = store.snapshot.serviceStatus else {
            return "状态未知"
        }
        let loaded = status.launchd.loaded ? "后台运行中" : "后台已停止"
        return "\(store.snapshot.summary.title) · \(loaded) · \(status.pollSeconds)s 轮询"
    }

    private var summaryColor: Color {
        switch store.snapshot.summary {
        case .running: .green
        case .attention: .orange
        case .stopped: .secondary
        case .unknown: .red
        }
    }

    private var runReportSection: some View {
        SectionBlock(title: "最近运行") {
            if let report = store.snapshot.serviceStatus?.lastRunReport {
                InfoGrid(rows: [
                    ("时间", SmartShadowFormatters.shortTimestamp(report.timestamp)),
                    ("处理", "\(report.processedCount ?? 0)"),
                    ("错误", "\(report.errorCount ?? 0)"),
                    ("新鲜度", report.fresh == true ? "新鲜 · \(SmartShadowFormatters.relativeAge(seconds: report.ageSeconds))" : "过期")
                ])
            } else {
                Text("还没有运行报告")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var eventKitAndSourcesSection: some View {
        SectionBlock(title: "权限与来源") {
            if let status = store.snapshot.serviceStatus {
                InfoGrid(rows: [
                    ("Calendar", status.eventKit.calendar ?? "未知"),
                    ("Reminders", status.eventKit.reminders ?? "未知")
                ])

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(status.sourceDoctor.sources) { source in
                        HStack {
                            Image(systemName: source.readyToEnable ? "checkmark.circle" : "exclamationmark.circle")
                                .foregroundStyle(source.readyToEnable ? .green : .orange)
                            Text(source.name)
                                .lineLimit(1)
                            Spacer()
                            Text(source.enabled ? "已启用" : "未启用")
                                .foregroundStyle(.secondary)
                            if !source.readyToEnable {
                                Text(source.blockers.joined(separator: ", "))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        .font(.caption)
                    }
                }
            } else {
                Text("无法读取权限与来源状态")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recentItemsSection: some View {
        SectionBlock(title: "最近事项") {
            let items = Array((store.snapshot.healthStatus?.recent ?? []).prefix(5))
            if items.isEmpty {
                Text("暂无最近事项")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .lineLimit(1)
                            Text([item.domain, item.risk, item.status].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = store.lastActionMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("刷新") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r")

                Button("启动") {
                    Task { await store.startService() }
                }
                .disabled(store.isWorking)

                Button("停止") {
                    Task { await store.stopService() }
                }
                .disabled(store.isWorking)

                Button("报告") {
                    Task { await store.writeReport() }
                }
                .disabled(store.isWorking)
            }

            HStack {
                Button("打开项目") {
                    store.openProject()
                }
                Button("打开日志") {
                    store.openLogs()
                }
                Spacer()
                Button("退出") {
                    NSApp.terminate(nil)
                }
            }
        }
        .buttonStyle(.bordered)
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "xmark.octagon.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(3)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct InfoGrid: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(rows, id: \.0) { label, value in
                GridRow {
                    Text(label)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .lineLimit(1)
                }
            }
        }
    }
}
