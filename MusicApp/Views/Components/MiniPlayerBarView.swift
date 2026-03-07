import SwiftUI

struct MiniPlayerBarView: View {
    let song: Song
    let title: String
    let isPlaying: Bool
    let playbackProgress: PlaybackProgressState
    let onTogglePlayPause: () -> Void
    let onNext: () -> Void
    let onHide: () -> Void
    let onStop: () -> Void
    let onOpen: () -> Void
    @State private var revealClose = false
    @State private var dragOffsetX: CGFloat = 0
    @State private var suppressOpenUntil = Date.distantPast
    @State private var suppressButtonsUntil = Date.distantPast

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                HStack(spacing: 12) {
                    Button(action: handleOpenTap) {
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)

                    Button(action: handleTogglePlayPause) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .frame(width: 34, height: 34)
                            .foregroundStyle(isPlaying ? .yellow : .green)
                    }
                    .contentShape(.interaction, Rectangle().inset(by: -12))
                    .buttonStyle(.plain)

                    Button(action: handleNext) {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .frame(width: 34, height: 34)
                    }
                    .contentShape(.interaction, Rectangle().inset(by: -12))
                    .buttonStyle(.plain)

                    Button(action: handleStop) {
                        Image(systemName: "stop.fill")
                            .font(.title3)
                            .frame(width: 34, height: 34)
                            .foregroundStyle(.red)
                    }
                    .contentShape(.interaction, Rectangle().inset(by: -12))
                    .buttonStyle(.plain)
                }
                .padding(.trailing, revealClose ? 34 : 0)
                .offset(x: dragOffsetX)
                .animation(.easeOut(duration: 0.2), value: revealClose)

                if revealClose {
                    Button(action: handleHide) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .frame(width: 30, height: 30)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            MiniPlayerProgressBar(state: playbackProgress)
            .padding(.horizontal, 12)
            .frame(height: 2)
        }
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.04), lineWidth: 0.35)
                }
                .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 3)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    let x = value.translation.width
                    suppressOpenUntil = Date().addingTimeInterval(0.25)
                    suppressButtonsUntil = Date().addingTimeInterval(0.25)
                    if x < 0 {
                        dragOffsetX = max(x, -56)
                        if x < -20 {
                            revealClose = true
                        }
                    } else {
                        dragOffsetX = 0
                        if x > 12 {
                            revealClose = false
                        }
                    }
                }
                .onEnded { value in
                    suppressButtonsUntil = Date().addingTimeInterval(0.2)
                    withAnimation(.easeOut(duration: 0.2)) {
                        revealClose = value.translation.width < -20
                        dragOffsetX = 0
                    }
                }
        )
    }

    private func handleOpenTap() {
        if Date() < suppressOpenUntil || Date() < suppressButtonsUntil {
            return
        }
        onOpen()
    }

    private func handleTogglePlayPause() {
        guard Date() >= suppressButtonsUntil else { return }
        onTogglePlayPause()
    }

    private func handleNext() {
        guard Date() >= suppressButtonsUntil else { return }
        onNext()
    }

    private func handleStop() {
        guard Date() >= suppressButtonsUntil else { return }
        onStop()
    }

    private func handleHide() {
        guard Date() >= suppressButtonsUntil else { return }
        onHide()
    }
}

private struct MiniPlayerProgressBar: View {
    @ObservedObject var state: PlaybackProgressState

    private var clampedProgress: Double {
        min(max(state.progress, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(Color.green.opacity(0.9))
                    .frame(width: width * clampedProgress)
            }
        }
    }
}
