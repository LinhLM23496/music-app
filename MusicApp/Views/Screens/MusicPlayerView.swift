import SwiftUI

struct MusicPlayerView: View {
    let song: Song
    let controller: PlayerViewModel

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localizationViewModel: LocalizationViewModel
    @EnvironmentObject private var libraryViewModel: LibraryViewModel
    @EnvironmentObject private var playlistViewModel: PlaylistViewModel
    @StateObject private var uiState: MusicPlayerUIState
    @State private var showQueueSheet = false
    @State private var showPlaylistSheet = false
    @State private var showCreatePlaylistPrompt = false
    @State private var newPlaylistName = ""
    @State private var toastMessage: String?
    @State private var toastWorkItem: DispatchWorkItem?

    init(song: Song, controller: PlayerViewModel) {
        self.song = song
        self.controller = controller
        _uiState = StateObject(wrappedValue: MusicPlayerUIState(song: song, source: controller))
    }

    private func localized(_ key: String) -> String {
        Localizer.string(key, language: uiState.language)
    }

    var body: some View {
        ZStack {
            PlayerBackgroundView(accent: uiState.displaySong.accent)

            VStack(spacing: 24) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.title3.weight(.semibold))
                    }

                    Spacer()

                    Text(localized("player.now.playing"))
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

                PlayerArtworkView(song: uiState.displaySong, isPlaying: uiState.isPlaying)

                NowPlayingInfoView(
                    song: uiState.displaySong,
                    language: uiState.language,
                    isFavorite: libraryViewModel.favoriteIDs.contains(uiState.displaySong.id),
                    onToggleFavorite: { libraryViewModel.toggleFavorite(songID: uiState.displaySong.id) },
                    onAddToPlaylist: { showPlaylistSheet = true }
                )
                .padding(.horizontal, 24)

                PlaybackProgressSection(
                    state: uiState.playbackProgress,
                    fallbackDuration: uiState.playbackProgress.duration > 0 ? uiState.playbackProgress.duration : uiState.displaySong.duration,
                    onSeek: { controller.seek(to: $0) }
                )
                .padding(.horizontal, 24)

                HStack(spacing: 26) {
                    Button {
                        controller.toggleShuffle()
                    } label: {
                        Image(systemName: "shuffle")
                            .foregroundStyle(uiState.isShuffleOn ? .green : .white)
                    }

                    Button {
                        controller.previousSong()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title)
                    }

                    Button {
                        controller.togglePlayPause()
                    } label: {
                        Image(systemName: uiState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.white)
                    }

                    Button {
                        controller.nextSong()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title)
                    }

                    Button {
                        controller.cycleRepeatMode()
                    } label: {
                        Image(systemName: uiState.repeatMode.icon)
                            .foregroundStyle(uiState.repeatMode == .off ? .white : .green)
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 12) {
                    Menu {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                            Button {
                                controller.setPlaybackSpeed(speed)
                                controller.resumeLiveProgressUpdates()
                            } label: {
                                if speed == uiState.playbackSpeed {
                                    Label(String(format: "%.2fx", speed), systemImage: "checkmark")
                                } else {
                                    Text(String(format: "%.2fx", speed))
                                }
                            }
                        }
                    } label: {
                        Label("\(localized("player.speed")): \(String(format: "%.2fx", uiState.playbackSpeed))", systemImage: "speedometer")
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        controller.pauseLiveProgressUpdates(seconds: 2.0)
                    })
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08), in: Capsule())

                    Menu {
                        Button(localized("player.sleep.off")) {
                            controller.cancelSleepTimer()
                            controller.resumeLiveProgressUpdates()
                        }
                        Button(localized("player.sleep.5m")) {
                            controller.setSleepTimer(minutes: 5)
                            controller.resumeLiveProgressUpdates()
                        }
                        Button(localized("player.sleep.10m")) {
                            controller.setSleepTimer(minutes: 10)
                            controller.resumeLiveProgressUpdates()
                        }
                        Button(localized("player.sleep.15m")) {
                            controller.setSleepTimer(minutes: 15)
                            controller.resumeLiveProgressUpdates()
                        }
                        Button(localized("player.sleep.30m")) {
                            controller.setSleepTimer(minutes: 30)
                            controller.resumeLiveProgressUpdates()
                        }
                    } label: {
                        Label(localized("player.sleep.timer"), systemImage: "timer")
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        controller.pauseLiveProgressUpdates(seconds: 2.0)
                    })
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }
                .font(.subheadline)

                SleepTimerStatusView(text: uiState.sleepTimerText)

                Spacer()
            }
            .foregroundStyle(.white)
        }
        .onAppear {
            DispatchQueue.main.async {
                uiState.bind(to: controller)
                if !controller.isCurrentSong(song) {
                    controller.play(song: song)
                }
            }
        }
        .sheet(isPresented: $showQueueSheet) {
            queueSheet
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPlaylistSheet) {
            PlaylistPickerSheet(
                song: uiState.displaySong,
                playlists: playlistViewModel.playlists,
                language: uiState.language,
                onSelectPlaylist: { playlist in
                    let didAdd = playlistViewModel.toggleSong(uiState.displaySong, in: playlist.id)
                    showPlaylistSheet = false
                    let key = didAdd ? "playlist.add.song.success" : "playlist.remove.song.success"
                    showToast(localized(key))
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
        .alert(localized("playlist.create"), isPresented: $showCreatePlaylistPrompt) {
            TextField(localized("playlist.name"), text: $newPlaylistName)
            Button(localized("playlist.cancel"), role: .cancel) {
                newPlaylistName = ""
            }
            Button(localized("playlist.create.button")) {
                let trimmed = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                playlistViewModel.createPlaylist(name: trimmed)
                if let playlist = playlistViewModel.playlists.first {
                    _ = playlistViewModel.toggleSong(uiState.displaySong, in: playlist.id)
                    showToast(localized("playlist.create.and.add.success"))
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

    private var queueSheet: some View {
        NavigationStack {
            List(Array(uiState.queueSongs.enumerated()), id: \.offset) { index, queueSong in
                Button {
                    controller.playFromQueue(index: index)
                } label: {
                    HStack(spacing: 12) {
                        AlbumArtworkView(symbol: queueSong.coverSymbol, accent: queueSong.accent, cornerRadius: 10)
                            .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(queueSong.localizedTitle(for: uiState.language))
                                .lineLimit(1)
                            Text(queueSong.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if index == uiState.queueIndex {
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
            .navigationTitle(localized("player.queue"))
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
    @ObservedObject var state: PlaybackProgressState
    let fallbackDuration: Double
    let onSeek: (Double) -> Void

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { state.progress },
            set: { onSeek($0) }
        )
    }

    private var shownDuration: Double {
        state.duration > 0 ? state.duration : fallbackDuration
    }

    var body: some View {
        VStack(spacing: 4) {
            Slider(value: sliderBinding, in: 0...1)
                .tint(.green)

            HStack {
                Text(Self.timeText(progress: state.currentTime))
                Spacer()
                Text(Self.timeText(progress: shownDuration))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private static func timeText(progress: Double) -> String {
        let total = Int(progress)
        let minute = total / 60
        let second = total % 60
        return String(format: "%d:%02d", minute, second)
    }
}

private struct SleepTimerStatusView: View {
    let text: String?

    var body: some View {
        Group {
            if let text {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
