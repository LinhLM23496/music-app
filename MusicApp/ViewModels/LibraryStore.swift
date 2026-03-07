import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published var songs: [Song]
    @Published var featuredSongIDs: [UUID]
    @Published var favoriteSongIDs: Set<UUID>

    init(songs: [Song], featuredSongIDs: [UUID], favoriteSongIDs: Set<UUID>) {
        self.songs = songs
        self.featuredSongIDs = featuredSongIDs
        self.favoriteSongIDs = favoriteSongIDs
    }

    var featuredSongs: [Song] {
        let featuredSet = Set(featuredSongIDs)
        return songs.filter { featuredSet.contains($0.id) }
    }

    var favoriteSongs: [Song] {
        songs.filter { favoriteSongIDs.contains($0.id) }
    }
}
