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

    init(
        libraryViewModel: LibraryViewModel,
        importViewModel: ImportViewModel,
        settingsStore: AppSettingsStore
    ) {
        self.libraryViewModel = libraryViewModel
        self.importViewModel = importViewModel
        self.settingsStore = settingsStore
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
        Localizer.string(key, language: settingsStore.language)
    }
}

@MainActor
final class AppContainer {
    static let shared = AppContainer()

    let catalogProvider: MusicCatalogProviding
    let authRepository: AuthRepository
    let trackRepository: TrackRepository
    let favoritesRepository: FavoritesRepository

    private init() {
        catalogProvider = MockMusicCatalogProvider()
        authRepository = UserDefaultsAuthRepository()
        trackRepository = RemoteFirstTrackRepository(
            remoteDataSource: MockRemoteAPITrackDataSource(provider: catalogProvider),
            localCache: InMemoryTrackLocalCache(),
            fallbackProvider: catalogProvider
        )
        favoritesRepository = UserDefaultsFavoritesRepository()
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

    func makePlayerViewModel(libraryDataSource: LibraryPlaybackDataProviding) -> PlayerViewModel {
        PlayerViewModel(
            settingsStore: .shared,
            libraryDataSource: libraryDataSource
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
