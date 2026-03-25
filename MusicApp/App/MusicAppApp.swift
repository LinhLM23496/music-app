//
//  MusicAppApp.swift
//  MusicApp
//
//  Created by Linh Le on 6/3/26.
//

import SwiftUI

@MainActor
final class AppContainer {
    static let shared = AppContainer()

    let catalogProvider: MusicCatalogProviding
    let authRepository: AuthRepository
    let trackRepository: TrackRepository
    let favoritesRepository: FavoritesRepository
    let playlistRepository: PlaylistRepository
    let apiClient: APIClient
    let mediaJobService: MediaJobServicing

    private init() {
        catalogProvider = MockMusicCatalogProvider()
        authRepository = UserDefaultsAuthRepository()
        trackRepository = RemoteFirstTrackRepository(
            remoteDataSource: MockRemoteAPITrackDataSource(provider: catalogProvider),
            localCache: InMemoryTrackLocalCache(),
            fallbackProvider: catalogProvider
        )
        favoritesRepository = UserDefaultsFavoritesRepository()
        playlistRepository = UserDefaultsPlaylistRepository()
        apiClient = URLSessionAPIClient(baseURL: APIConstants.baseURL)
        mediaJobService = LiveMediaJobService(apiClient: apiClient)
    }

    func makeAuthViewModel() -> AuthViewModel {
        AuthViewModel(authRepository: authRepository)
    }

    func makeLibraryViewModel() -> LibraryViewModel {
        LibraryViewModel(
            trackRepository: trackRepository,
            favoritesRepository: favoritesRepository
        )
    }

    func makePlaylistViewModel() -> PlaylistViewModel {
        PlaylistViewModel(playlistRepository: playlistRepository)
    }
}

@main
struct MusicAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
