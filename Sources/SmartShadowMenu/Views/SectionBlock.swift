import SwiftUI

struct SectionBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
