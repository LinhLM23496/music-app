import SwiftUI

struct SongRowView: View {
    let song: Song
    let title: String
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 12) {
            AlbumArtworkView(
                symbol: song.coverSymbol,
                accent: song.accent,
                localFilePath: song.localFilePath,
                cornerRadius: 12
            )
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
