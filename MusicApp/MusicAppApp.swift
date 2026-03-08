//
//  MusicAppApp.swift
//  MusicApp
//
//  Created by Linh Le on 6/3/26.
//

import SwiftUI
import Combine

@MainActor
final class PlayerLibraryDataSource: LibraryPlaybackDataProviding {
    private let libraryViewModel: LibraryViewModel
    private let importViewModel: ImportViewModel
    private let settingsStore: AppSettingsStore
    private let localizationService: LocalizationProviding

    init(
        libraryViewModel: LibraryViewModel,
        importViewModel: ImportViewModel,
        settingsStore: AppSettingsStore,
        localizationService: LocalizationProviding
    ) {
        self.libraryViewModel = libraryViewModel
        self.importViewModel = importViewModel
        self.settingsStore = settingsStore
        self.localizationService = localizationService
    }

    var songs: [Song] {
        libraryViewModel.tracks
    }

    var importedSongs: [Song] {
        importViewModel.importedSongs
    }

    var language: AppLanguage {
        settingsStore.language
    }

    var languagePublisher: AnyPublisher<AppLanguage, Never> {
        settingsStore.$language.eraseToAnyPublisher()
    }

    func localized(_ key: String) -> String {
        localizationService.string(key, language: settingsStore.language)
    }
}

@MainActor
final class AppContainer {
    static let shared = AppContainer()

    let catalogProvider: MusicCatalogProviding
    let authRepository: AuthRepository
    let trackRepository: TrackRepository
    let favoritesRepository: FavoritesRepository
    let playlistRepository: PlaylistRepository

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

    func makePlayerViewModel(libraryDataSource: LibraryPlaybackDataProviding) -> PlayerViewModel {
        PlayerViewModel(
            settingsStore: .shared,
            libraryDataSource: libraryDataSource,
            nowPlayingService: SystemNowPlayingService()
        )
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
