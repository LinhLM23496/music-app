import Foundation
import Combine

@MainActor
final class PlaylistViewModel: ObservableObject {
    let source: any PlaylistFeatureControlling
    private var cancellables = Set<AnyCancellable>()

    init(source: any PlaylistFeatureControlling) {
        self.source = source
        source.changePublisher
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var playlists: [Playlist] { source.playlists }
    var songs: [Song] { source.songs }
    var favoriteSongIDs: Set<UUID> { source.favoriteSongIDs }

    func localized(_ key: String) -> String { source.localized(key) }
    func localizedSongTitle(_ song: Song) -> String { source.localizedSongTitle(song) }
    func localizedPlaylistName(_ playlist: Playlist) -> String { source.localizedPlaylistName(playlist) }
    func songsCountText(_ count: Int) -> String { source.songsCountText(count) }
    func songs(in playlist: Playlist) -> [Song] { source.songs(in: playlist) }
    func createPlaylist(name: String) { source.createPlaylist(name: name) }
    func deletePlaylist(at offsets: IndexSet) { source.deletePlaylist(at: offsets) }
    func addSong(_ song: Song, to playlistID: UUID) { source.addSong(song, to: playlistID) }
}
