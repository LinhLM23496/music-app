import SwiftUI

struct JobStatusCardView<Content: View>: View {
    let title: String
    let progress: Double
    @ViewBuilder let content: () -> Content

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            ProgressView(value: clampedProgress)
                .tint(.green)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 10)
    }
}
