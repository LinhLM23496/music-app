import SwiftUI

struct MiniPlayerBarView: View {
    let song: Song
    let title: String
    let isPlaying: Bool
    let onTogglePlayPause: () -> Void
    let onNext: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    AlbumArtworkView(symbol: song.coverSymbol, accent: song.accent, cornerRadius: 10)
                        .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(song.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Button(action: onTogglePlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            Button(action: onNext) {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
