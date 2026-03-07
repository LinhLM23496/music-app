import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settingsStore: AppSettingsStore
    @StateObject private var appVM: MusicLibraryViewModel
    @StateObject private var homeVM: HomeViewModel
    @StateObject private var playlistVM: PlaylistViewModel
    @StateObject private var infoVM: InfoViewModel
    @StateObject private var playerVM: PlayerViewModel

    init() {
        let settings = AppSettingsStore.shared
        let app = MusicLibraryViewModel(settingsStore: .shared)
        _settingsStore = StateObject(wrappedValue: settings)
        _appVM = StateObject(wrappedValue: app)
        _homeVM = StateObject(wrappedValue: HomeViewModel(source: app))
        _playlistVM = StateObject(wrappedValue: PlaylistViewModel(source: app))
        _infoVM = StateObject(wrappedValue: InfoViewModel(source: app, settingsStore: settings))
        _playerVM = StateObject(wrappedValue: PlayerViewModel(source: app))
    }

    var body: some View {
        TabView {
            HomeTabView(vm: homeVM)
                .tabItem {
                    Label(playerVM.localized("tab.home"), systemImage: "house.fill")
                }

            PlaylistTabView(vm: playlistVM)
                .tabItem {
                    Label(playerVM.localized("tab.playlist"), systemImage: "music.note.list")
                }

            InfoTabView(vm: infoVM)
                .tabItem {
                    Label(playerVM.localized("tab.info"), systemImage: "person.crop.circle")
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if playerVM.shouldShowMiniPlayer, let currentSong = playerVM.currentSong {
                MiniPlayerBarView(
                    song: currentSong,
                    title: playerVM.localizedSongTitle(currentSong),
                    isPlaying: playerVM.isPlaying,
                    playbackProgress: playerVM.playbackProgress,
                    onTogglePlayPause: { playerVM.togglePlayPause() },
                    onNext: { playerVM.nextSong() },
                    onHide: { playerVM.hideMiniPlayer() },
                    onStop: { playerVM.stopAndResetPlayback() },
                    onOpen: { playerVM.presentPlayer(for: currentSong) }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 56)
            }
        }
        .tint(.green)
        .preferredColorScheme(.dark)
        .task {
            if scenePhase == .active {
                DispatchQueue.main.async {
                    appVM.handleSceneDidBecomeActive()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                DispatchQueue.main.async {
                    appVM.handleSceneDidBecomeActive()
                }
            } else if newPhase == .inactive || newPhase == .background {
                DispatchQueue.main.async {
                    appVM.savePlaybackSnapshotNow()
                }
            }
        }
        .sheet(item: $playerVM.playerSheetSong) { song in
            MusicPlayerView(song: song, vm: playerVM)
        }
    }
}
