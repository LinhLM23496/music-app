import Foundation
import Combine

@MainActor
final class PlaylistStore: ObservableObject {
    @Published var playlists: [Playlist]

    init(playlists: [Playlist]) {
        self.playlists = playlists
    }

    func createPlaylist(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(trimmed.prefix(PlaylistUseCases.maxPlaylistNameLength))
        guard !limited.isEmpty else { return }

        playlists.insert(
            Playlist(
                id: UUID(),
                nameEN: limited,
                nameVI: limited,
                coverSymbol: "music.note.list",
                songIDs: []
            ),
            at: 0
        )
    }

    func deletePlaylist(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where playlists.indices.contains(index) {
            playlists.remove(at: index)
        }
    }

    func addSong(_ song: Song, to playlistID: UUID) {
        guard let playlistIndex = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let legacyID = song.id.uuidString
        if !playlists[playlistIndex].songIDs.contains(song.stableID) && !playlists[playlistIndex].songIDs.contains(legacyID) {
            playlists[playlistIndex].songIDs.append(song.stableID)
            playlists[playlistIndex].coverSymbol = song.coverSymbol
        }
    }
}
