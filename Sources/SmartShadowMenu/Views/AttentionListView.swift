import SmartShadowMenuCore
import SwiftUI

struct AttentionListView: View {
    let items: [AttentionItem]

    var body: some View {
        SectionBlock(title: "注意项") {
            if items.isEmpty {
                Label("没有需要处理的注意项", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.code)
                                    .font(.caption.weight(.semibold))
                                if let source = item.source {
                                    Text(source)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(item.message)
                                .lineLimit(2)
                            if let command = item.suggestedCommand {
                                Text(command)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}
