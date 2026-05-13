import SwiftUI
import Combine

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var playerHeroNamespace
    private let playerHeroAnimation = Animation.spring(response: 0.75, dampingFraction: 0.86)
    @StateObject private var settingsStore: AppSettingsStore
    @StateObject private var localizationViewModel: LocalizationViewModel
    @StateObject private var importViewModel: ImportViewModel
    @StateObject private var playlistViewModel: PlaylistViewModel
    @StateObject private var authViewModel: AuthViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var playbackController: PlaybackController
    @StateObject private var downloadCenter: DownloadCenter

    init() {
        let container = AppContainer.shared
        let settings = AppSettingsStore.shared
        let localizationViewModel = LocalizationViewModel(
            settingsStore: settings,
            service: BundleLocalizationService()
        )
        let libraryViewModel = container.makeLibraryViewModel()
        let importViewModel = ImportViewModel(settingsStore: settings)
        let playlistViewModel = container.makePlaylistViewModel()
        let playbackContextStore = PlaybackContextStore()

        let trackResolver = DefaultTrackResolver(
            librarySongsProvider: { libraryViewModel.tracks },
            importedSongsProvider: { importViewModel.importedSongs }
        )

        let playbackPersistence = UserDefaultsPlaybackPersistence()
        let playerEngine = AVPlayerEngine()
        let mergeSongs: ([Song], [Song]) -> [Song] = { primary, secondary in
            var merged = primary
            var seenStableIDs = Set(primary.map(\.stableID))
            for song in secondary where !seenStableIDs.contains(song.stableID) {
                merged.append(song)
                seenStableIDs.insert(song.stableID)
            }
            return merged
        }

        let playbackController = PlaybackController(
            playerEngine: playerEngine,
            contextStore: playbackContextStore,
            playbackPersistence: playbackPersistence,
            trackResolver: trackResolver,
            nowPlayingService: SystemNowPlayingService(),
            availableTracksProvider: {
                let librarySongs = libraryViewModel.tracks
                let importedSongs = importViewModel.importedSongs
                return mergeSongs(librarySongs, importedSongs)
            },
            favoriteTracksProvider: {
                let favoriteIDs = libraryViewModel.favoriteIDs
                guard !favoriteIDs.isEmpty else { return [] }

                let libraryFavorites = libraryViewModel.tracks.filter { favoriteIDs.contains($0.id) }
                let importedFavorites = importViewModel.importedSongs.filter { favoriteIDs.contains($0.id) }
                return mergeSongs(libraryFavorites, importedFavorites)
            }
        )

        _playbackController = StateObject(wrappedValue: playbackController)

        _settingsStore = StateObject(wrappedValue: settings)
        _localizationViewModel = StateObject(wrappedValue: localizationViewModel)
        _importViewModel = StateObject(wrappedValue: importViewModel)
        _playlistViewModel = StateObject(wrappedValue: playlistViewModel)
        _authViewModel = StateObject(wrappedValue: container.makeAuthViewModel())
        _libraryViewModel = StateObject(wrappedValue: libraryViewModel)
        _downloadCenter = StateObject(wrappedValue: container.downloadCenter)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                HomeTabView()
                    .tabItem {
                        Label(localizationViewModel.t("tab.home"), systemImage: "house.fill")
                    }

                PlaylistTabView()
                    .tabItem {
                        Label(localizationViewModel.t("tab.playlist"), systemImage: "music.note.list")
                    }

                InfoTabView()
                    .tabItem {
                        Label(localizationViewModel.t("tab.info"), systemImage: "person.crop.circle")
                    }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if playbackController.shouldShowMiniPlayer, let currentSong = playbackController.currentSong {
                    MiniPlayerBarView(
                        song: currentSong,
                        title: currentSong.localizedTitle(for: settingsStore.language),
                        isPlaying: playbackController.playerState.isPlaying,
                        currentTime: playbackController.playerState.currentTime,
                        duration: playbackController.playerState.duration,
                        progress: playbackController.playerState.progress,
                        heroNamespace: playerHeroNamespace,
                        onTogglePlayPause: { playbackController.togglePlayPause() },
                        onNext: { playbackController.next() },
                        onHide: { playbackController.hideAndCleanMiniPlayer() },
                        onStop: { playbackController.stop() },
                        onOpen: {
                            withAnimation(playerHeroAnimation) {
                                playbackController.presentPlayer()
                            }
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 56)
                }
            }

            if playbackController.isPlayerSheetVisible, let song = playbackController.currentSong {
                MusicPlayerOverlay(
                    song: song,
                    heroNamespace: playerHeroNamespace,
                    dismiss: {
                        withAnimation(playerHeroAnimation) {
                            playbackController.dismissPlayer()
                        }
                    }
                )
                .environmentObject(playbackController)
                .environmentObject(localizationViewModel)
                .environmentObject(libraryViewModel)
                .environmentObject(playlistViewModel)
                .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                .zIndex(10)
            }

            if downloadCenter.showResumePrompt {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                        Text(localizationViewModel.t("downloads.resume.prompt"))
                            .font(.subheadline)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Button(localizationViewModel.t("downloads.resume.no")) {
                            downloadCenter.dismissResumePrompt()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                        Button(localizationViewModel.t("downloads.resume.yes")) {
                            downloadCenter.resumeInterruptedJobs()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.green)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(20)
            }
        }
        .animation(playerHeroAnimation, value: playbackController.isPlayerSheetVisible)
        .animation(.easeInOut(duration: 0.22), value: downloadCenter.showResumePrompt)
        .tint(.green)
        .preferredColorScheme(.dark)
        .environmentObject(localizationViewModel)
        .environmentObject(importViewModel)
        .environmentObject(playlistViewModel)
        .environmentObject(settingsStore)
        .environmentObject(authViewModel)
        .environmentObject(libraryViewModel)
        .environmentObject(playbackController)
        .environmentObject(downloadCenter)
        .onAppear {
            if scenePhase == .active {
                playbackController.restoreSnapshotIfNeeded()
            }
            syncPlaylistSongs()
        }
        .onReceive(
            Publishers.CombineLatest(
                libraryViewModel.$tracks,
                importViewModel.$importedTracks
            )
        ) { _, _ in
            syncPlaylistSongs()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                DispatchQueue.main.async {
                    playbackController.restoreSnapshotIfNeeded()
                }
                syncPlaylistSongs()
            } else if newPhase == .inactive || newPhase == .background {
                DispatchQueue.main.async {
                    playbackController.saveSnapshot()
                }
            }
        }
    }

    private func syncPlaylistSongs() {
        playlistViewModel.syncSongs(with: mergeSongs(libraryViewModel.tracks, importViewModel.importedSongs))
    }

    private func mergeSongs(_ primary: [Song], _ secondary: [Song]) -> [Song] {
        var merged = primary
        var seenStableIDs = Set(primary.map(\.stableID))
        for song in secondary where !seenStableIDs.contains(song.stableID) {
            merged.append(song)
            seenStableIDs.insert(song.stableID)
        }
        return merged
    }
}

private struct MusicPlayerOverlay: View {
    let song: Song
    let heroNamespace: Namespace.ID
    let dismiss: () -> Void
    
    @State private var dragOffsetY: CGFloat = 0
    @State private var isDragging = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            MusicPlayerView(song: song, heroNamespace: heroNamespace, onDismiss: dismiss)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(y: dragOffsetY)
                .scaleEffect(playerScale, anchor: .top)
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            guard value.translation.height > 0 else { return }
                            isDragging = true
                            dragOffsetY = value.translation.height
                        }
                        .onEnded { value in
                            let shouldDismiss = value.translation.height > 140 || value.predictedEndTranslation.height > 220
                            if shouldDismiss {
                                dismiss()
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                                    dragOffsetY = 0
                                    isDragging = false
                                }
                            }
                        }
                )
        }
        .onChange(of: song.id) { _, _ in
            dragOffsetY = 0
            isDragging = false
        }
    }
    
    private var playerScale: CGFloat {
        let progress = min(max(dragOffsetY / 600, 0), 1)
        return 1 - (progress * 0.06)
    }
}
