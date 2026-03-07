import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settingsStore = AppSettingsStore.shared
    @StateObject private var vm = MusicLibraryViewModel(settingsStore: .shared)

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
            if vm.shouldShowMiniPlayer, let currentSong = vm.currentSong {
                MiniPlayerBarView(
                    song: currentSong,
                    title: vm.localizedSongTitle(currentSong),
                    isPlaying: vm.isPlaying,
                    playbackProgress: vm.playbackProgress,
                    onTogglePlayPause: { vm.togglePlayPause() },
                    onNext: { vm.nextSong() },
                    onHide: { vm.hideMiniPlayer() },
                    onStop: { vm.stopAndResetPlayback() },
                    onOpen: { vm.presentPlayer(for: currentSong) }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 56)
            }
        }
        .tint(.green)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .environmentObject(settingsStore)
        .task {
            if scenePhase == .active {
                DispatchQueue.main.async {
                    vm.handleSceneDidBecomeActive()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                DispatchQueue.main.async {
                    vm.handleSceneDidBecomeActive()
                }
            } else if newPhase == .inactive || newPhase == .background {
                DispatchQueue.main.async {
                    vm.savePlaybackSnapshotNow()
                }
            }
        }
        .sheet(item: $vm.playerSheetSong) { song in
            MusicPlayerView(song: song, controller: vm)
        }
    }
}
