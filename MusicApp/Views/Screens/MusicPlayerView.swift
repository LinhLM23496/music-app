import SwiftUI

struct MusicPlayerView: View {
    let song: Song
    @ObservedObject var vm: PlayerViewModel

    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiState: MusicPlayerUIState
    @State private var showQueueSheet = false

    init(song: Song, vm: PlayerViewModel) {
        self.song = song
        self.vm = vm
        _uiState = StateObject(wrappedValue: MusicPlayerUIState(song: song, source: vm.appVM))
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
                    isFavorite: uiState.favoriteSongIDs.contains(uiState.displaySong.id),
                    onToggleFavorite: { vm.appVM.toggleFavorite(for: uiState.displaySong) }
                )
                .padding(.horizontal, 24)

                PlaybackProgressSection(
                    state: uiState.playbackProgress,
                    fallbackDuration: uiState.playbackProgress.duration > 0 ? uiState.playbackProgress.duration : uiState.displaySong.duration,
                    onSeek: { vm.appVM.seek(to: $0) }
                )
                .padding(.horizontal, 24)

                HStack(spacing: 26) {
                    Button {
                        vm.appVM.isShuffleOn.toggle()
                    } label: {
                        Image(systemName: "shuffle")
                            .foregroundStyle(uiState.isShuffleOn ? .green : .white)
                    }

                    Button {
                        vm.appVM.previousSong()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title)
                    }

                    Button {
                        vm.togglePlayPause()
                    } label: {
                        Image(systemName: uiState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.white)
                    }

                    Button {
                        vm.nextSong()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title)
                    }

                    Button {
                        vm.appVM.cycleRepeatMode()
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
                                vm.appVM.setPlaybackSpeed(speed)
                                vm.appVM.resumeLiveProgressUpdates()
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
                        vm.appVM.pauseLiveProgressUpdates(seconds: 2.0)
                    })
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08), in: Capsule())

                    Menu {
                        Button(localized("player.sleep.off")) {
                            vm.appVM.cancelSleepTimer()
                            vm.appVM.resumeLiveProgressUpdates()
                        }
                        Button(localized("player.sleep.5m")) {
                            vm.appVM.setSleepTimer(minutes: 5)
                            vm.appVM.resumeLiveProgressUpdates()
                        }
                        Button(localized("player.sleep.10m")) {
                            vm.appVM.setSleepTimer(minutes: 10)
                            vm.appVM.resumeLiveProgressUpdates()
                        }
                        Button(localized("player.sleep.15m")) {
                            vm.appVM.setSleepTimer(minutes: 15)
                            vm.appVM.resumeLiveProgressUpdates()
                        }
                        Button(localized("player.sleep.30m")) {
                            vm.appVM.setSleepTimer(minutes: 30)
                            vm.appVM.resumeLiveProgressUpdates()
                        }
                    } label: {
                        Label(localized("player.sleep.timer"), systemImage: "timer")
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        vm.appVM.pauseLiveProgressUpdates(seconds: 2.0)
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
                uiState.bind(to: vm.appVM)
                if !vm.appVM.isCurrentSong(song) {
                    vm.appVM.play(song: song)
                }
            }
        }
        .sheet(isPresented: $showQueueSheet) {
            queueSheet
                .presentationDetents([.medium, .large])
        }
    }

    private var queueSheet: some View {
        NavigationStack {
            List(Array(uiState.queueSongs.enumerated()), id: \.offset) { index, queueSong in
                Button {
                    vm.appVM.playFromQueue(index: index)
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

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundStyle(isFavorite ? .pink : .white)
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
