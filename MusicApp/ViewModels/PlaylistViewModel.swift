import Foundation
import Combine

@MainActor
final class PlaylistViewModel: ObservableObject {
    let appVM: MusicLibraryViewModel
    private var cancellables = Set<AnyCancellable>()

    init(appVM: MusicLibraryViewModel) {
        self.appVM = appVM
        appVM.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var playlists: [Playlist] { appVM.playlists }
    var songs: [Song] { appVM.songs }
    var favoriteSongIDs: Set<UUID> { appVM.favoriteSongIDs }

    func localized(_ key: String) -> String { appVM.localized(key) }
    func localizedSongTitle(_ song: Song) -> String { appVM.localizedSongTitle(song) }
    func localizedPlaylistName(_ playlist: Playlist) -> String { appVM.localizedPlaylistName(playlist) }
    func songsCountText(_ count: Int) -> String { appVM.songsCountText(count) }
    func songs(in playlist: Playlist) -> [Song] { appVM.songs(in: playlist) }
    func createPlaylist(name: String) { appVM.createPlaylist(name: name) }
    func deletePlaylist(at offsets: IndexSet) { appVM.deletePlaylist(at: offsets) }
    func addSong(_ song: Song, to playlistID: UUID) { appVM.addSong(song, to: playlistID) }
}
