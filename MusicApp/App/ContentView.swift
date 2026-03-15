import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settingsStore: AppSettingsStore
    @StateObject private var localizationViewModel: LocalizationViewModel
    @StateObject private var importViewModel: ImportViewModel
    @StateObject private var playlistViewModel: PlaylistViewModel
    @StateObject private var authViewModel: AuthViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var playbackController: PlaybackController

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
        let presentationStore = PlaybackPresentationStore()

        let trackResolver = DefaultTrackResolver(
            librarySongsProvider: { libraryViewModel.tracks },
            importedSongsProvider: { importViewModel.importedSongs }
        )

        let playbackPersistence = UserDefaultsPlaybackPersistence()
        let playerEngine = AVPlayerEngine()

        let playbackController = PlaybackController(
            playerEngine: playerEngine,
            contextStore: playbackContextStore,
            presentationStore: presentationStore,
            playbackPersistence: playbackPersistence,
            trackResolver: trackResolver,
            nowPlayingService: SystemNowPlayingService()
        )

        _playbackController = StateObject(wrappedValue: playbackController)

        _settingsStore = StateObject(wrappedValue: settings)
        _localizationViewModel = StateObject(wrappedValue: localizationViewModel)
        _importViewModel = StateObject(wrappedValue: importViewModel)
        _playlistViewModel = StateObject(wrappedValue: playlistViewModel)
        _authViewModel = StateObject(wrappedValue: container.makeAuthViewModel())
        _libraryViewModel = StateObject(wrappedValue: libraryViewModel)
    }

    var body: some View {
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
                    onTogglePlayPause: { playbackController.togglePlayPause() },
                    onNext: { playbackController.next() },
                    onHide: { playbackController.hideAndCleanPlayback() },
                    onStop: { playbackController.stop() },
                    onOpen: { playbackController.presentPlayer(for: currentSong.id) }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 56)
            }
        }
        .tint(.green)
        .preferredColorScheme(.dark)
        .environmentObject(localizationViewModel)
        .environmentObject(importViewModel)
        .environmentObject(playlistViewModel)
        .environmentObject(settingsStore)
        .environmentObject(authViewModel)
        .environmentObject(libraryViewModel)
        .environmentObject(playbackController)
        .onAppear {
            if scenePhase == .active {
                playbackController.restoreSnapshotIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                DispatchQueue.main.async {
                    playbackController.restoreSnapshotIfNeeded()
                }
            } else if newPhase == .inactive || newPhase == .background {
                DispatchQueue.main.async {
                    playbackController.saveSnapshot()
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { playbackController.presentedTrackID != nil },
                set: { if !$0 { playbackController.dismissPlayer() } }
            )
        ) {
            if let song = playbackController.presentedSong {
                MusicPlayerView(song: song)
                    .environmentObject(playbackController)
                    .environmentObject(localizationViewModel)
                    .environmentObject(libraryViewModel)
                    .environmentObject(playlistViewModel)
            }
        }
    }
}
