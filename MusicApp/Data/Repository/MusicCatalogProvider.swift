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
    let avatarSymbol: String
    let appVersion: String

    static func guest() -> AuthUser {
        AuthUser(
            id: "guest",
            displayName: "Guest",
            avatarSymbol: "person.crop.circle.badge.xmark",
            appVersion: currentAppVersion()
        )
    }

    static func demo(name: String) -> AuthUser {
        AuthUser(
            id: "local-demo-user",
            displayName: name,
            avatarSymbol: "person.crop.circle.badge.checkmark",
            appVersion: currentAppVersion()
        )
    }

    private static func currentAppVersion() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let version, !version.isEmpty else { return "1.0.0" }
        return version
    }
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

protocol PlaylistRepository {
    func loadPlaylists() -> [Playlist]
    func savePlaylists(_ playlists: [Playlist])
}

final class UserDefaultsAuthRepository: AuthRepository {
    private let defaults: UserDefaults
    private let key = "auth.current_user_name"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadCurrentUser() -> AuthUser? {
        guard let name = defaults.string(forKey: key), !name.isEmpty else { return nil }
        return AuthUser.demo(name: name)
    }

    func signInDemo() -> AuthUser {
        let user = AuthUser.demo(name: "LinhLe")
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

final class UserDefaultsPlaylistRepository: PlaylistRepository {
    private struct PlaylistSnapshot: Codable {
        let id: UUID
        let nameEN: String
        let nameVI: String
        let coverSymbol: String
        let songIDs: [String]

        private enum CodingKeys: String, CodingKey {
            case id
            case nameEN
            case nameVI
            case coverSymbol
            case songIDs
        }

        init(id: UUID, nameEN: String, nameVI: String, coverSymbol: String, songIDs: [String]) {
            self.id = id
            self.nameEN = nameEN
            self.nameVI = nameVI
            self.coverSymbol = coverSymbol
            self.songIDs = songIDs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            nameEN = try container.decode(String.self, forKey: .nameEN)
            nameVI = try container.decode(String.self, forKey: .nameVI)
            coverSymbol = try container.decode(String.self, forKey: .coverSymbol)

            if let stableIDs = try? container.decode([String].self, forKey: .songIDs) {
                songIDs = stableIDs
            } else {
                let legacyIDs = (try? container.decode([UUID].self, forKey: .songIDs)) ?? []
                songIDs = legacyIDs.map(\.uuidString)
            }
        }
    }

    private let defaults: UserDefaults
    private let key = "playlist.saved_items"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadPlaylists() -> [Playlist] {
        guard
            let data = defaults.data(forKey: key),
            let snapshots = try? JSONDecoder().decode([PlaylistSnapshot].self, from: data)
        else {
            return []
        }

        return snapshots.map {
            Playlist(
                id: $0.id,
                nameEN: $0.nameEN,
                nameVI: $0.nameVI,
                coverSymbol: $0.coverSymbol,
                songIDs: $0.songIDs
            )
        }
    }

    func savePlaylists(_ playlists: [Playlist]) {
        let snapshots = playlists.map {
            PlaylistSnapshot(
                id: $0.id,
                nameEN: $0.nameEN,
                nameVI: $0.nameVI,
                coverSymbol: $0.coverSymbol,
                songIDs: $0.songIDs
            )
        }

        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        defaults.set(data, forKey: key)
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
        let stableID: String?
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
        let songIDs: [String]

        private enum CodingKeys: String, CodingKey {
            case id
            case nameEN
            case nameVI
            case coverSymbol
            case songIDs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            nameEN = try container.decode(String.self, forKey: .nameEN)
            nameVI = try container.decode(String.self, forKey: .nameVI)
            coverSymbol = try container.decode(String.self, forKey: .coverSymbol)

            if let stableIDs = try? container.decode([String].self, forKey: .songIDs) {
                songIDs = stableIDs
            } else {
                let legacyIDs = (try? container.decode([UUID].self, forKey: .songIDs)) ?? []
                songIDs = legacyIDs.map(\.uuidString)
            }
        }
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
                stableID: Self.normalizedStableID(item.stableID ?? item.audioFileName),
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
        let stableSongIDSet = Set(songs.map(\.stableID))
        let featured = payload.featuredSongIDs.filter { songIDSet.contains($0) }

        let playlists = payload.playlists.map { item in
            Playlist(
                id: item.id,
                nameEN: item.nameEN,
                nameVI: item.nameVI,
                coverSymbol: item.coverSymbol,
                songIDs: item.songIDs.filter { stableSongIDSet.contains($0) }
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

    private static func normalizedStableID(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
