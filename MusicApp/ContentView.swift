import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settingsStore: AppSettingsStore
    @StateObject private var localizationViewModel: LocalizationViewModel
    @StateObject private var importViewModel: ImportViewModel
    @StateObject private var playlistViewModel: PlaylistViewModel
    @StateObject private var authViewModel: AuthViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var playerViewModel: PlayerViewModel

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
        let playerDataSource = PlayerLibraryDataSource(
            libraryViewModel: libraryViewModel,
            importViewModel: importViewModel,
            playlistViewModel: playlistViewModel,
            settingsStore: settings,
            localizationService: BundleLocalizationService()
        )
        _settingsStore = StateObject(wrappedValue: settings)
        _localizationViewModel = StateObject(wrappedValue: localizationViewModel)
        _importViewModel = StateObject(wrappedValue: importViewModel)
        _playlistViewModel = StateObject(wrappedValue: playlistViewModel)
        _authViewModel = StateObject(wrappedValue: container.makeAuthViewModel())
        _libraryViewModel = StateObject(wrappedValue: libraryViewModel)
        _playerViewModel = StateObject(wrappedValue: container.makePlayerViewModel(libraryDataSource: playerDataSource))
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
            if playerViewModel.shouldShowMiniPlayer, let currentSong = playerViewModel.currentSong {
                MiniPlayerBarView(
                    song: currentSong,
                    title: playerViewModel.localizedSongTitle(currentSong),
                    isPlaying: playerViewModel.isPlaying,
                    playbackProgress: playerViewModel.playbackProgress,
                    onTogglePlayPause: { playerViewModel.togglePlayPause() },
                    onNext: { playerViewModel.nextSong() },
                    onHide: { playerViewModel.hideMiniPlayer() },
                    onStop: { playerViewModel.stopAndResetPlayback() },
                    onOpen: { playerViewModel.presentPlayer(for: currentSong) }
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
        .environmentObject(playerViewModel)
        .task {
            if scenePhase == .active {
                DispatchQueue.main.async {
                    playerViewModel.handleSceneDidBecomeActive()
                }
            }

        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                DispatchQueue.main.async {
                    playerViewModel.handleSceneDidBecomeActive()
                }
            } else if newPhase == .inactive || newPhase == .background {
                DispatchQueue.main.async {
                    playerViewModel.savePlaybackSnapshotNow()
                }
            }
        }
        .sheet(item: $playerViewModel.playerSheetSong) { song in
            MusicPlayerView(song: song, controller: playerViewModel)
                .environmentObject(localizationViewModel)
                .environmentObject(libraryViewModel)
                .environmentObject(playlistViewModel)
        }
    }
}
