import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settingsStore: AppSettingsStore
    @StateObject private var localizationViewModel: LocalizationViewModel
    @StateObject private var importViewModel: ImportViewModel
    @StateObject private var playlistViewModel: PlaylistViewModel
    @StateObject private var authViewModel: AuthViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var playerCoordinator: PlayerCoordinator

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
        let playerSessionStore = PlayerSessionStore()
        let playerPresentationStore = PlayerPresentationStore()

        let trackResolver = DefaultTrackResolver(
            librarySongsProvider: { libraryViewModel.tracks },
            importedSongsProvider: { importViewModel.importedSongs }
        )

        let playerPersistence = UserDefaultsPlayerPersistence()
        let playbackEngine = AVPlaybackEngine()

        let playerCoordinator = PlayerCoordinator(
            engine: playbackEngine,
            sessionStore: playerSessionStore,
            playerPresentationStore: playerPresentationStore,
            playerPersistence: playerPersistence,
            trackResolver: trackResolver,
            nowPlayingService: SystemNowPlayingService()
        )

        _playerCoordinator = StateObject(wrappedValue: playerCoordinator)

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
            if playerCoordinator.shouldShowMiniPlayer, let currentSong = playerCoordinator.currentSong {
                MiniPlayerBarView(
                    song: currentSong,
                    title: currentSong.localizedTitle(for: settingsStore.language),
                    isPlaying: playerCoordinator.playbackState.isPlaying,
                    currentTime: playerCoordinator.playbackState.currentTime,
                    duration: playerCoordinator.playbackState.duration,
                    progress: playerCoordinator.playbackState.progress,
                    onTogglePlayPause: { playerCoordinator.togglePlayPause() },
                    onNext: { playerCoordinator.next() },
                    onHide: { playerCoordinator.hideMiniPlayer() },
                    onStop: { playerCoordinator.stop() },
                    onOpen: { playerCoordinator.presentPlayer(for: currentSong.id) }
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
        .environmentObject(playerCoordinator)
        .task {
            if scenePhase == .active {
                DispatchQueue.main.async {
                    playerCoordinator.restoreSnapshotIfNeeded()
                }
            }

        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                DispatchQueue.main.async {
                    playerCoordinator.restoreSnapshotIfNeeded()
                }
            } else if newPhase == .inactive || newPhase == .background {
                DispatchQueue.main.async {
                    playerCoordinator.saveSnapshot()
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { playerCoordinator.presentedTrackID != nil },
                set: { if !$0 { playerCoordinator.dismissPlayer() } }
            )
        ) {
            if let song = playerCoordinator.presentedSong {
                MusicPlayerView(song: song)
                    .environmentObject(playerCoordinator)
                    .environmentObject(localizationViewModel)
                    .environmentObject(libraryViewModel)
                    .environmentObject(playlistViewModel)
            }
        }
    }
}
