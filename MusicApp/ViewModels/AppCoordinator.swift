import Foundation
import Combine

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private var coordinatorStateVersion: Int = 0

    let settingsStore: AppSettingsStore
    let homeFeatureStore: HomeFeatureStore
    let playlistFeatureStore: PlaylistFeatureStore
    let infoFeatureStore: InfoFeatureStore
    let playerFeatureStore: PlayerFeatureStore

    private var didPerformInitialActivationWork = false

    init(settingsStore: AppSettingsStore, catalogProvider: MusicCatalogProviding) {
        self.settingsStore = settingsStore

        let initialCatalog = catalogProvider.loadInitialCatalog()
        let libraryStore = LibraryStore(
            songs: initialCatalog.songs,
            featuredSongIDs: initialCatalog.featuredSongIDs,
            favoriteSongIDs: initialCatalog.favoriteSongIDs
        )
        let playlistStore = PlaylistStore(playlists: initialCatalog.playlists)
        let deviceMediaStore = DeviceMediaStore()
        let userInfoStore = UserInfoStore()
        let playerUIStore = PlayerUIStore()
        let deviceMediaService = DeviceMediaService()

        let queueStore = QueueStore(
            queueSongs: initialCatalog.songs,
            queueIndex: 0,
            isShuffleOn: settingsStore.shuffleEnabled,
            repeatMode: settingsStore.repeatMode
        )
        let playbackController = PlaybackController()
        let snapshotStore = PlaybackSnapshotStore(settingsStore: settingsStore)

        let playerFeatureStore = PlayerFeatureStore(
            settingsStore: settingsStore,
            libraryStore: libraryStore,
            deviceMediaStore: deviceMediaStore,
            deviceMediaService: deviceMediaService,
            playerUIStore: playerUIStore,
            queueStore: queueStore,
            playbackController: playbackController,
            snapshotStore: snapshotStore
        )
        self.playerFeatureStore = playerFeatureStore

        let homeFeatureStore = HomeFeatureStore(
            settingsStore: settingsStore,
            libraryStore: libraryStore,
            deviceMediaStore: deviceMediaStore,
            deviceMediaService: deviceMediaService,
            playerStore: playerFeatureStore
        )
        self.homeFeatureStore = homeFeatureStore

        self.playlistFeatureStore = PlaylistFeatureStore(
            settingsStore: settingsStore,
            libraryStore: libraryStore,
            playlistStore: playlistStore
        )

        self.infoFeatureStore = InfoFeatureStore(
            settingsStore: settingsStore,
            userInfoStore: userInfoStore,
            deviceMediaStore: deviceMediaStore,
            deviceMediaService: deviceMediaService
        )
    }

    convenience init() {
        self.init(settingsStore: .shared, catalogProvider: MockMusicCatalogProvider())
    }

    func handleSceneDidBecomeActive() {
        if !didPerformInitialActivationWork {
            didPerformInitialActivationWork = true
            playerFeatureStore.restorePlaybackSnapshotIfAvailable()
        }
        homeFeatureStore.refreshDeviceTracks()
    }

    func savePlaybackSnapshotNow() {
        playerFeatureStore.savePlaybackSnapshotNow()
    }
}
