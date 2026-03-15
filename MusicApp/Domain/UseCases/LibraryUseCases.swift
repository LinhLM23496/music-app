import Foundation

struct LibraryUseCases {
    func song(for id: UUID, in songs: [Song]) -> Song? {
        songs.first(where: { $0.id == id })
    }

    func suggestedQueue(
        for song: Song,
        songs: [Song],
        importedSongs: [Song]
    ) -> [Song] {
        if songs.contains(where: { $0.id == song.id }) {
            return songs
        }

        if song.localFilePath != nil, !importedSongs.isEmpty {
            return importedSongs
        }

        return [song]
    }
}
