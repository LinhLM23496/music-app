import SwiftUI

struct MusicPlayerView: View {
    let song: Song

    @EnvironmentObject private var localizationViewModel: LocalizationViewModel
    @EnvironmentObject private var libraryViewModel: LibraryViewModel
    @EnvironmentObject private var playlistViewModel: PlaylistViewModel
    @EnvironmentObject private var playbackController: PlaybackController

    @State private var showQueueSheet = false
    @State private var showPlaylistSheet = false
    @State private var showCreatePlaylistPrompt = false
    @State private var newPlaylistName = ""
    @State private var toastMessage: String?
    @State private var toastWorkItem: DispatchWorkItem?

    private var currentSong: Song {
        playbackController.currentSong ?? song
    }

    private var language: AppLanguage {
        localizationViewModel.language
    }

    var body: some View {
        ZStack {
            PlayerBackgroundView(accent: currentSong.accent)

            VStack(spacing: 24) {
                HStack {
                    Button {
                        playbackController.dismissPlayer()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.title3.weight(.semibold))
                    }

                    Spacer()

                    Text(localizationViewModel.t("player.now.playing"))
                        .font(.headline)

                    Spacer()

                    Button {
                        showQueueSheet = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.title3.weight(.semibold))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                PlayerArtworkView(song: currentSong, isPlaying: playbackController.playerState.isPlaying)

                NowPlayingInfoView(
                    song: currentSong,
                    language: language,
                    isFavorite: libraryViewModel.favoriteIDs.contains(currentSong.id),
                    onToggleFavorite: { libraryViewModel.toggleFavorite(songID: currentSong.id) },
                    onAddToPlaylist: { showPlaylistSheet = true }
                )
                .padding(.horizontal, 24)

                PlaybackProgressSection(
                    currentTime: playbackController.playerState.currentTime,
                    duration: shownDuration,
                    progress: playbackController.playerState.progress,
                    onSeek: { playbackController.seek(to: $0) }
                )
                .padding(.horizontal, 24)

                HStack(spacing: 26) {
                    Button {
                        playbackController.toggleShuffle()
                    } label: {
                        Image(systemName: "shuffle")
                            .foregroundStyle(playbackController.shuffleEnabled ? .green : .white)
                    }

                    Button {
                        playbackController.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title)
                    }

                    Button {
                        playbackController.togglePlayPause()
                    } label: {
                        Image(systemName: playbackController.playerState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.white)
                    }

                    Button {
                        playbackController.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title)
                    }

                    Button {
                        playbackController.cycleRepeatMode()
                    } label: {
                        Image(systemName: playbackController.repeatMode.icon)
                            .foregroundStyle(playbackController.repeatMode == .off ? .white : .green)
                    }
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach([0.75 as Float, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button {
                            playbackController.setPlaybackSpeed(speed)
                        } label: {
                            if abs(playbackController.playbackSpeed - speed) < 0.001 {
                                Label(String(format: "%.2fx", speed), systemImage: "checkmark")
                            } else {
                                Text(String(format: "%.2fx", speed))
                            }
                        }
                    }
                } label: {
                    Label(
                        "\(localizationViewModel.t("player.speed")): \(String(format: "%.2fx", playbackController.playbackSpeed))",
                        systemImage: "speedometer"
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
                .font(.subheadline)

                Spacer()
            }
            .foregroundStyle(.white)
        }
        .sheet(isPresented: $showQueueSheet) {
            queueSheet
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPlaylistSheet) {
            PlaylistPickerSheet(
                song: currentSong,
                playlists: playlistViewModel.playlists,
                language: language,
                onSelectPlaylist: { playlist in
                    let didAdd = playlistViewModel.toggleSong(currentSong, in: playlist.id)
                    showPlaylistSheet = false
                    let key = didAdd ? "playlist.add.song.success" : "playlist.remove.song.success"
                    showToast(localizationViewModel.t(key))
                },
                onCreatePlaylist: {
                    showPlaylistSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showCreatePlaylistPrompt = true
                    }
                }
            )
            .environmentObject(localizationViewModel)
            .presentationDetents([.medium, .large])
        }
        .alert(localizationViewModel.t("playlist.create"), isPresented: $showCreatePlaylistPrompt) {
            TextField(localizationViewModel.t("playlist.name"), text: $newPlaylistName)
            Button(localizationViewModel.t("playlist.cancel"), role: .cancel) {
                newPlaylistName = ""
            }
            Button(localizationViewModel.t("playlist.create.button")) {
                let trimmed = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }

                let beforeIDs = Set(playlistViewModel.playlists.map(\.id))
                playlistViewModel.createPlaylist(name: trimmed)
                if let createdPlaylist = playlistViewModel.playlists.first(where: { !beforeIDs.contains($0.id) }) {
                    _ = playlistViewModel.toggleSong(currentSong, in: createdPlaylist.id)
                    showToast(localizationViewModel.t("playlist.create.and.add.success"))
                }
                newPlaylistName = ""
            }
        }
        .overlay(alignment: .top) {
            if let toastMessage {
                AppToastView(message: toastMessage)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: toastMessage != nil)
    }

    private var shownDuration: Float {
        let duration = playbackController.playerState.duration
        return duration > 0 ? duration : Float(currentSong.duration)
    }

    private var queueSheet: some View {
        NavigationStack {
            List(Array(playbackController.currentQueueSongs.enumerated()), id: \.offset) { index, queueSong in
                Button {
                    playbackController.playFromQueue(at: index)
                } label: {
                    HStack(spacing: 12) {
                        AlbumArtworkView(symbol: queueSong.coverSymbol, accent: queueSong.accent, cornerRadius: 10)
                            .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(queueSong.localizedTitle(for: language))
                                .lineLimit(1)
                            Text(queueSong.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if index == playbackController.currentIndex {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(localizationViewModel.t("player.queue"))
        }
    }

    private func showToast(_ message: String) {
        toastWorkItem?.cancel()
        toastMessage = message

        let workItem = DispatchWorkItem {
            toastMessage = nil
        }
        toastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }
}

private struct PlayerBackgroundView: View {
    let accent: Color

    var body: some View {
        LinearGradient(
            colors: [accent.opacity(0.65), .black, .black],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct PlayerArtworkView: View {
    let song: Song
    let isPlaying: Bool

    var body: some View {
        AlbumArtworkView(symbol: song.coverSymbol, accent: song.accent, cornerRadius: 24)
            .frame(width: 300, height: 300)
            .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 16)
            .scaleEffect(isPlaying ? 1 : 0.97)
            .animation(.easeInOut(duration: 0.35), value: isPlaying)
    }
}

private struct NowPlayingInfoView: View {
    let song: Song
    let language: AppLanguage
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onAddToPlaylist: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.localizedTitle(for: language))
                    .font(.title2.bold())
                    .lineLimit(1)
                Text(song.artist)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 16) {
                Button(action: onAddToPlaylist) {
                    Image(systemName: "text.badge.plus")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundStyle(isFavorite ? .pink : .white)
                }
            }
        }
    }
}

private struct PlaylistPickerSheet: View {
    let song: Song
    let playlists: [Playlist]
    let language: AppLanguage
    let onSelectPlaylist: (Playlist) -> Void
    let onCreatePlaylist: () -> Void

    @EnvironmentObject private var localizationViewModel: LocalizationViewModel
    @EnvironmentObject private var playlistViewModel: PlaylistViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(playlists) { playlist in
                    Button {
                        onSelectPlaylist(playlist)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            AlbumArtworkView(symbol: playlist.coverSymbol, accent: song.accent, cornerRadius: 12)
                                .frame(width: 52, height: 52)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(localizationViewModel.playlistName(playlist))
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(localizationViewModel.songsCountText(playlist.songIDs.count))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: playlistViewModel.containsSong(song.id, in: playlist.id) ? "checkmark.circle.fill" : "plus.circle.fill")
                                .foregroundStyle(playlistViewModel.containsSong(song.id, in: playlist.id) ? .green : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .safeAreaPadding(.bottom, 90)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(localizationViewModel.t("playlist.add.to"))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    dismiss()
                    onCreatePlaylist()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                        Text(localizationViewModel.t("playlist.new"))
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(Color.green, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)
            }
        }
    }
}

private struct PlaybackProgressSection: View {
    let currentTime: Float
    let duration: Float
    let progress: Float
    let onSeek: (Float) -> Void

    private var sliderBinding: Binding<Float> {
        Binding(
            get: { progress },
            set: { onSeek($0) }
        )
    }

    var body: some View {
        VStack(spacing: 4) {
            Slider(value: sliderBinding, in: 0...1)
                .tint(.green)

            HStack {
                Text(Self.timeText(seconds: currentTime))
                Spacer()
                Text(Self.timeText(seconds: duration))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private static func timeText(seconds: Float) -> String {
        let total = Int(seconds)
        let minute = total / 60
        let second = total % 60
        return String(format: "%d:%02d", minute, second)
    }
}
