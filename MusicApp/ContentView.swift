import SwiftUI

struct ContentView: View {
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
            if vm.hasPlaybackSession, let currentSong = vm.currentSong {
                MiniPlayerBarView(
                    song: currentSong,
                    title: vm.localizedSongTitle(currentSong),
                    isPlaying: vm.isPlaying,
                    onTogglePlayPause: { vm.togglePlayPause() },
                    onNext: { vm.nextSong() },
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
        .sheet(item: $selectedSong) { song in
            MusicPlayerView(song: song, controller: vm)
        }
    }
}
