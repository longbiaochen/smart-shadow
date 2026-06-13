import SmartShadowMenuCore
import SwiftUI

struct AttentionListView: View {
    let items: [AttentionItem]

    var body: some View {
        SectionBlock(title: "注意项") {
            if items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("没有需要处理的注意项")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                VStack(spacing: 1) {
                    ForEach(items) { item in
                        AttentionRow(item: item)
                        if item.id != items.last?.id {
                            Divider()
                                .padding(.leading, 28)
                        }
                    }
                }
                .padding(10)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct AttentionRow: View {
    let item: AttentionItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .font(.caption.weight(.semibold))
                    if let source = item.source {
                        Text(source)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(item.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let command = item.suggestedCommand {
                    Text(command)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }

    private var displayTitle: String {
        switch item.code {
        case "source_blocked": "来源未就绪"
        case "audit_report_missing": "审计引用缺失"
        case "last_run_stale": "最近运行过期"
        case "launchd_not_loaded": "后台未加载"
        default: item.code
        }
    }
}
