import Foundation

struct PlaylistUseCases {
    func createPlaylist(name: String, in playlists: [Playlist]) -> [Playlist] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return playlists }

        var next = playlists
        next.insert(
            Playlist(
                id: UUID(),
                nameEN: trimmed,
                nameVI: trimmed,
                coverSymbol: "music.note.list",
                songIDs: []
            ),
            at: 0
        )
        return next
    }

    func deletePlaylists(at offsets: IndexSet, in playlists: [Playlist]) -> [Playlist] {
        var next = playlists
        for index in offsets.sorted(by: >) where next.indices.contains(index) {
            next.remove(at: index)
        }
        return next
    }

    func addSong(_ song: Song, to playlistID: UUID, in playlists: [Playlist]) -> [Playlist] {
        guard let playlistIndex = playlists.firstIndex(where: { $0.id == playlistID }) else {
            return playlists
        }

        var next = playlists
        if !next[playlistIndex].songIDs.contains(song.id) {
            next[playlistIndex].songIDs.append(song.id)
            next[playlistIndex].coverSymbol = song.coverSymbol
        }
        return next
    }

    func songs(in playlist: Playlist, allSongs: [Song]) -> [Song] {
        let map = Dictionary(uniqueKeysWithValues: allSongs.map { ($0.id, $0) })
        return playlist.songIDs.compactMap { map[$0] }
    }
}
