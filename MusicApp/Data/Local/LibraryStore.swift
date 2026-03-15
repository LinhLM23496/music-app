import Foundation
import Combine

@MainActor
protocol LibraryCatalogDataProviding: AnyObject {
    var tracks: [Song] { get }
    var tracksPublisher: AnyPublisher<[Song], Never> { get }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published var songs: [Song]

    init(songs: [Song]) {
        self.songs = songs
    }
}

@MainActor
final class LibraryViewModel: ObservableObject, LibraryCatalogDataProviding {
    @Published private(set) var tracks: [Song] = []
    @Published private(set) var featuredIDs: [UUID] = []
    @Published var favoriteIDs: Set<UUID> = []

    private let trackRepository: TrackRepository
    private let favoritesRepository: FavoritesRepository

    init(trackRepository: TrackRepository, favoritesRepository: FavoritesRepository) {
        self.trackRepository = trackRepository
        self.favoritesRepository = favoritesRepository
        load()
    }

    func load() {
        let catalog = trackRepository.fetchInitialCatalog()
        tracks = catalog.songs
        featuredIDs = catalog.featuredSongIDs
        favoriteIDs = favoritesRepository.loadFavoriteIDs()
    }

    var featuredTracks: [Song] {
        let featuredSet = Set(featuredIDs)
        return tracks.filter { featuredSet.contains($0.id) }
    }

    func toggleFavorite(songID: UUID) {
        if favoriteIDs.contains(songID) {
            favoriteIDs.remove(songID)
        } else {
            favoriteIDs.insert(songID)
        }
        favoritesRepository.saveFavoriteIDs(favoriteIDs)
    }

    func setFavoriteIDs(_ ids: Set<UUID>) {
        guard favoriteIDs != ids else { return }
        favoriteIDs = ids
        favoritesRepository.saveFavoriteIDs(ids)
    }

    var tracksPublisher: AnyPublisher<[Song], Never> {
        $tracks.eraseToAnyPublisher()
    }
}
