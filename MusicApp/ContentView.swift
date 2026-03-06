import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settingsStore = AppSettingsStore.shared
    @StateObject private var vm = MusicLibraryViewModel()
    @State private var selectedSong: Song?

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
                    onOpen: { selectedSong = currentSong }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 56)
            }
        }
        .tint(.green)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .environmentObject(settingsStore)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                vm.refreshDeviceTracks()
            }
        }
        .sheet(item: $selectedSong) { song in
            MusicPlayerView(song: song, controller: vm)
        }
    }
}
