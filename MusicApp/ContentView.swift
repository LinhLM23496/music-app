import SwiftUI

struct ContentView: View {
    @StateObject private var settingsStore = AppSettingsStore.shared
    @StateObject private var vm = MusicLibraryViewModel()

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
        .tint(.green)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .environmentObject(settingsStore)
    }
}
