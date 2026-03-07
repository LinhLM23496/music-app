import Foundation
import SwiftUI

struct InitialCatalogData {
    let songs: [Song]
    let featuredSongIDs: [UUID]
    let playlists: [Playlist]
}

protocol MusicCatalogProviding {
    func loadInitialCatalog() -> InitialCatalogData
}

struct AuthUser {
    let id: String
    let displayName: String
}

protocol AuthRepository {
    func loadCurrentUser() -> AuthUser?
    func signInDemo() -> AuthUser
    func signOut()
}

protocol TrackRepository {
    func fetchInitialCatalog() -> InitialCatalogData
}

protocol TrackRemoteDataSource {
    func fetchCatalog() -> InitialCatalogData?
}

protocol TrackLocalCache {
    func loadCatalog() -> InitialCatalogData?
    func saveCatalog(_ catalog: InitialCatalogData)
}

protocol FavoritesRepository {
    func loadFavoriteIDs() -> Set<UUID>
    func saveFavoriteIDs(_ ids: Set<UUID>)
}

final class UserDefaultsAuthRepository: AuthRepository {
    private let defaults: UserDefaults
    private let key = "auth.current_user_name"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadCurrentUser() -> AuthUser? {
        guard let name = defaults.string(forKey: key), !name.isEmpty else { return nil }
        return AuthUser(id: "local-demo-user", displayName: name)
    }

    func signInDemo() -> AuthUser {
        let user = AuthUser(id: "local-demo-user", displayName: "LinhLe")
        defaults.set(user.displayName, forKey: key)
        return user
    }

    func signOut() {
        defaults.removeObject(forKey: key)
    }
}

struct CatalogTrackRepository: TrackRepository {
    private let provider: MusicCatalogProviding

    init(provider: MusicCatalogProviding) {
        self.provider = provider
    }

    func fetchInitialCatalog() -> InitialCatalogData {
        provider.loadInitialCatalog()
    }
}

struct MockRemoteAPITrackDataSource: TrackRemoteDataSource {
    private let provider: MusicCatalogProviding

    init(provider: MusicCatalogProviding) {
        self.provider = provider
    }

    func fetchCatalog() -> InitialCatalogData? {
        provider.loadInitialCatalog()
    }
}

final class InMemoryTrackLocalCache: TrackLocalCache {
    private var cachedCatalog: InitialCatalogData?

    func loadCatalog() -> InitialCatalogData? {
        cachedCatalog
    }

    func saveCatalog(_ catalog: InitialCatalogData) {
        cachedCatalog = catalog
    }
}

struct RemoteFirstTrackRepository: TrackRepository {
    private let remoteDataSource: TrackRemoteDataSource
    private let localCache: TrackLocalCache
    private let fallbackProvider: MusicCatalogProviding

    init(
        remoteDataSource: TrackRemoteDataSource,
        localCache: TrackLocalCache,
        fallbackProvider: MusicCatalogProviding
    ) {
        self.remoteDataSource = remoteDataSource
        self.localCache = localCache
        self.fallbackProvider = fallbackProvider
    }

    func fetchInitialCatalog() -> InitialCatalogData {
        if let remote = remoteDataSource.fetchCatalog(), !remote.songs.isEmpty {
            localCache.saveCatalog(remote)
            return remote
        }

        if let cached = localCache.loadCatalog(), !cached.songs.isEmpty {
            return cached
        }

        let fallback = fallbackProvider.loadInitialCatalog()
        localCache.saveCatalog(fallback)
        return fallback
    }
}

final class UserDefaultsFavoritesRepository: FavoritesRepository {
    private let defaults: UserDefaults
    private let key = "favorites.song_ids"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadFavoriteIDs() -> Set<UUID> {
        guard let raw = defaults.array(forKey: key) as? [String] else { return [] }
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    func saveFavoriteIDs(_ ids: Set<UUID>) {
        defaults.set(ids.map(\.uuidString), forKey: key)
    }
}

struct MockMusicCatalogProvider: MusicCatalogProviding {
    private enum Constants {
        static let mockCatalogFileName = "music_catalog_mock"
        static let mockCatalogExtension = "json"
    }

    private struct CatalogPayload: Decodable {
        let songs: [SongPayload]
        let featuredSongIDs: [UUID]
        let playlists: [PlaylistPayload]
    }

    private struct SongPayload: Decodable {
        let id: UUID
        let titleEN: String
        let titleVI: String
        let artist: String
        let album: String
        let coverSymbol: String
        let audioFileName: String
        let duration: Double
        let accent: String
    }

    private struct PlaylistPayload: Decodable {
        let id: UUID
        let nameEN: String
        let nameVI: String
        let coverSymbol: String
        let songIDs: [UUID]
    }

    func loadInitialCatalog() -> InitialCatalogData {
        guard
            let payload = loadPayload(),
            !payload.songs.isEmpty
        else {
            return InitialCatalogData(songs: [], featuredSongIDs: [], playlists: [])
        }

        let songs = payload.songs.map { item in
            Song(
                id: item.id,
                titleEN: item.titleEN,
                titleVI: item.titleVI,
                artist: item.artist,
                album: item.album,
                coverSymbol: item.coverSymbol,
                audioFileName: item.audioFileName,
                localFilePath: nil,
                duration: item.duration,
                accent: color(for: item.accent)
            )
        }

        let songIDSet = Set(songs.map(\.id))
        let featured = payload.featuredSongIDs.filter { songIDSet.contains($0) }

        let playlists = payload.playlists.map { item in
            Playlist(
                id: item.id,
                nameEN: item.nameEN,
                nameVI: item.nameVI,
                coverSymbol: item.coverSymbol,
                songIDs: item.songIDs.filter { songIDSet.contains($0) }
            )
        }

        return InitialCatalogData(songs: songs, featuredSongIDs: featured, playlists: playlists)
    }

    private func loadPayload() -> CatalogPayload? {
        guard let url = mockCatalogURL() else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CatalogPayload.self, from: data)
    }

    private func mockCatalogURL() -> URL? {
        if let fileURL = Bundle.main.url(
            forResource: Constants.mockCatalogFileName,
            withExtension: Constants.mockCatalogExtension,
            subdirectory: "Resources/MockData"
        ) {
            return fileURL
        }

        if let fileURL = Bundle.main.url(
            forResource: Constants.mockCatalogFileName,
            withExtension: Constants.mockCatalogExtension,
            subdirectory: "MockData"
        ) {
            return fileURL
        }

        return Bundle.main.url(
            forResource: Constants.mockCatalogFileName,
            withExtension: Constants.mockCatalogExtension
        )
    }

    private func color(for rawValue: String) -> Color {
        switch rawValue.lowercased() {
        case "pink":
            return .pink
        case "blue":
            return .blue
        case "mint":
            return .mint
        case "orange":
            return .orange
        case "purple":
            return .purple
        case "cyan":
            return .cyan
        case "green":
            return .green
        case "red":
            return .red
        case "yellow":
            return .yellow
        default:
            return .gray
        }
    }
}
