import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settingsStore: AppSettingsStore
    @StateObject private var vm: MusicLibraryViewModel
    @StateObject private var importViewModel: ImportViewModel
    @StateObject private var playlistViewModel: PlaylistViewModel
    @StateObject private var authViewModel: AuthViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var playerViewModel: PlayerViewModel

    init() {
        let container = AppContainer.shared
        let settings = AppSettingsStore.shared
        let libraryViewModel = container.makeLibraryViewModel()
        let importViewModel = ImportViewModel(settingsStore: settings)
        let playlistViewModel = PlaylistViewModel(catalogProvider: container.catalogProvider)
        let playerDataSource = PlayerLibraryDataSource(
            libraryViewModel: libraryViewModel,
            importViewModel: importViewModel,
            settingsStore: settings
        )
        let libraryVM = MusicLibraryViewModel(
            settingsStore: settings,
            catalogSource: libraryViewModel,
            importViewModel: importViewModel
        )

        _settingsStore = StateObject(wrappedValue: settings)
        _vm = StateObject(wrappedValue: libraryVM)
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
                    Label(vm.localized("tab.home"), systemImage: "house.fill")
                }

            PlaylistTabView()
                .tabItem {
                    Label(vm.localized("tab.playlist"), systemImage: "music.note.list")
                }

            InfoTabView()
                .tabItem {
                    Label(vm.localized("tab.info"), systemImage: "person.crop.circle")
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
        .environmentObject(vm)
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
                .environmentObject(libraryViewModel)
        }
    }
}
