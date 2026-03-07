import Foundation

struct LibraryUseCases {
    func featuredSongs(songs: [Song], featuredSongIDs: [UUID]) -> [Song] {
        let featuredSet = Set(featuredSongIDs)
        return songs.filter { featuredSet.contains($0.id) }
    }

    func favoriteSongs(songs: [Song], favoriteSongIDs: Set<UUID>) -> [Song] {
        songs.filter { favoriteSongIDs.contains($0.id) }
    }

    func song(for id: UUID, in songs: [Song]) -> Song? {
        songs.first(where: { $0.id == id })
    }

    func toggleFavorite(songID: UUID, currentFavorites: Set<UUID>) -> Set<UUID> {
        var favorites = currentFavorites
        if favorites.contains(songID) {
            favorites.remove(songID)
        } else {
            favorites.insert(songID)
        }
        return favorites
    }

    func suggestedQueue(
        for song: Song,
        songs: [Song],
        deviceTracks: [LocalAudioTrack],
        trackToSong: (LocalAudioTrack) -> Song
    ) -> [Song] {
        if songs.contains(where: { $0.id == song.id }) {
            return songs
        }

        if song.localFilePath != nil {
            let deviceQueue = deviceTracks.map(trackToSong)
            if !deviceQueue.isEmpty {
                return deviceQueue
            }
        }

        return [song]
    }
}
