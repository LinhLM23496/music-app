import SwiftUI

struct AlbumArtworkView: View {
    let symbol: String
    let accent: Color
    var cornerRadius: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [accent.opacity(0.95), .black.opacity(0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .padding(22)
                    .foregroundStyle(.white.opacity(0.9))
            }
    }
}
