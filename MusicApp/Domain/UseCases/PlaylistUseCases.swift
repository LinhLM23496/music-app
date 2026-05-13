import Foundation

struct PlaylistUseCases {
    static let maxPlaylistNameLength = 50

    func createPlaylist(name: String, in playlists: [Playlist]) -> [Playlist] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(trimmed.prefix(Self.maxPlaylistNameLength))
        guard !limited.isEmpty else { return playlists }

        var next = playlists
        next.insert(
            Playlist(
                id: UUID(),
                nameEN: limited,
                nameVI: limited,
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

    func renamePlaylist(id: UUID, name: String, in playlists: [Playlist]) -> [Playlist] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let playlistIndex = playlists.firstIndex(where: { $0.id == id }) else {
            return playlists
        }

        var next = playlists
        next[playlistIndex].nameEN = trimmed
        next[playlistIndex].nameVI = trimmed
        return next
    }

    func addSong(_ song: Song, to playlistID: UUID, in playlists: [Playlist]) -> [Playlist] {
        guard let playlistIndex = playlists.firstIndex(where: { $0.id == playlistID }) else {
            return playlists
        }

        var next = playlists
        let legacyID = song.id.uuidString
        if !next[playlistIndex].songIDs.contains(song.stableID) && !next[playlistIndex].songIDs.contains(legacyID) {
            next[playlistIndex].songIDs.append(song.stableID)
            next[playlistIndex].coverSymbol = song.coverSymbol
        }
        return next
    }

    func removeSong(_ song: Song, from playlistID: UUID, in playlists: [Playlist]) -> [Playlist] {
        guard let playlistIndex = playlists.firstIndex(where: { $0.id == playlistID }) else {
            return playlists
        }

        var next = playlists
        let legacyID = song.id.uuidString
        next[playlistIndex].songIDs.removeAll { $0 == song.stableID || $0 == legacyID }
        if next[playlistIndex].songIDs.isEmpty {
            next[playlistIndex].coverSymbol = "music.note.list"
        }
        return next
    }

    func songs(in playlist: Playlist, allSongs: [Song]) -> [Song] {
        var map: [String: Song] = [:]
        for song in allSongs {
            // Keep the first encountered song for a stableID to avoid crashes
            // when two sources contain the same file name.
            if map[song.stableID] == nil {
                map[song.stableID] = song
            }
        }
        return playlist.songIDs.compactMap { map[$0] }
    }

    func moveSongs(in playlistID: UUID, from offsets: IndexSet, to destination: Int, in playlists: [Playlist]) -> [Playlist] {
        guard let playlistIndex = playlists.firstIndex(where: { $0.id == playlistID }) else {
            return playlists
        }

        var next = playlists
        var songIDs = next[playlistIndex].songIDs
        let movingItems = offsets.sorted().map { songIDs[$0] }

        for index in offsets.sorted(by: >) {
            songIDs.remove(at: index)
        }

        let adjustedDestination = offsets.filter { $0 < destination }.count
        let targetIndex = max(0, min(destination - adjustedDestination, songIDs.count))
        songIDs.insert(contentsOf: movingItems, at: targetIndex)
        next[playlistIndex].songIDs = songIDs
        return next
    }
}
