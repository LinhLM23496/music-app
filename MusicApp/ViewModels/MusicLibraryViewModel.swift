import SwiftUI
import Combine
import AVFoundation
import CryptoKit

@MainActor
final class MusicLibraryViewModel: ObservableObject {
    struct ImportResult {
        let importedCount: Int
        let skippedCount: Int
        let failedCount: Int
    }

    @Published var songs: [Song] {
        didSet { libraryStore.songs = songs }
    }
    @Published var deviceTracks: [LocalAudioTrack] {
        didSet { deviceMediaStore.deviceTracks = deviceTracks }
    }
    @Published var featuredSongIDs: [UUID] {
        didSet { libraryStore.featuredSongIDs = featuredSongIDs }
    }
    @Published var favoriteSongIDs: Set<UUID> {
        didSet { libraryStore.favoriteSongIDs = favoriteSongIDs }
    }
    @Published var playlists: [Playlist] {
        didSet { playlistStore.playlists = playlists }
    }

    var language: AppLanguage {
        get { settingsStore.language }
        set {
            if settingsStore.language != newValue {
                settingsStore.language = newValue
            }
        }
    }
    var languagePublisher: AnyPublisher<AppLanguage, Never> {
        settingsStore.$language.eraseToAnyPublisher()
    }
    var favoriteSongIDsPublisher: AnyPublisher<Set<UUID>, Never> {
        $favoriteSongIDs.eraseToAnyPublisher()
    }

    @Published var currentSongID: UUID?
    @Published var isPlaying = false
    let playbackProgress: PlaybackProgressState

    @Published var isShuffleOn: Bool {
        didSet {
            if settingsStore.shuffleEnabled != isShuffleOn {
                settingsStore.shuffleEnabled = isShuffleOn
            }
            if queueStore.isShuffleOn != isShuffleOn {
                queueStore.isShuffleOn = isShuffleOn
            }
        }
    }
    @Published var repeatMode: RepeatMode {
        didSet {
            if settingsStore.repeatMode != repeatMode {
                settingsStore.repeatMode = repeatMode
            }
            if queueStore.repeatMode != repeatMode {
                queueStore.repeatMode = repeatMode
            }
        }
    }

    @Published var queueSongs: [Song]
    @Published var queueIndex: Int
    @Published var playbackSpeed: Double = 1.0
    @Published var hasPlaybackSession = false
    @Published var isMiniPlayerHidden: Bool {
        didSet { playerUIStore.isMiniPlayerHidden = isMiniPlayerHidden }
    }
    @Published var playerSheetSong: Song? {
        didSet { playerUIStore.playerSheetSong = playerSheetSong }
    }
    @Published var sleepTimerRemaining: Double?
    @Published var musicStorageFolderPath: String {
        didSet { deviceMediaStore.musicStorageFolderPath = musicStorageFolderPath }
    }
    @Published var musicStorageFolderStatus: String {
        didSet { deviceMediaStore.musicStorageFolderStatus = musicStorageFolderStatus }
    }

    @Published var user: AppUser {
        didSet { userInfoStore.user = user }
    }

    private let settingsStore: AppSettingsStore
    private let libraryStore: LibraryStore
    private let playlistStore: PlaylistStore
    private let deviceMediaStore = DeviceMediaStore()
    private let deviceMediaService = DeviceMediaService()
    private let playerUIStore = PlayerUIStore()
    private let userInfoStore = UserInfoStore()

    private let queueStore: QueueStore
    private let playbackController: PlaybackController
    private let snapshotStore: PlaybackSnapshotStore
    private let libraryUseCases = LibraryUseCases()
    private let playlistUseCases = PlaylistUseCases()
    private lazy var playerCoordinator: PlayerCoordinator = {
        PlayerCoordinator(
            queueStore: queueStore,
            playbackController: playbackController,
            snapshotStore: snapshotStore,
            isSameTrack: isSameTrack,
            suggestedQueue: { [weak self] song in
                self?.suggestedQueue(for: song) ?? [song]
            },
            audioURLForSong: { [weak self] song in
                self?.deviceMediaService.audioURL(for: song)
            }
        )
    }()

    private let sleepTimerService = SleepTimerService()
    private let ioQueue = DispatchQueue(label: "com.musicapp.audio-io", qos: .userInitiated)

    private var cancellables = Set<AnyCancellable>()
    private var didPerformInitialActivationWork = false

    init(
        settingsStore: AppSettingsStore,
        catalogProvider: MusicCatalogProviding? = nil
    ) {
        self.settingsStore = settingsStore
        let initialShuffle = settingsStore.shuffleEnabled
        let initialRepeatMode = settingsStore.repeatMode
        isShuffleOn = initialShuffle
        repeatMode = initialRepeatMode

        let provider = catalogProvider ?? MockMusicCatalogProvider()
        let initialCatalog = provider.loadInitialCatalog()
        let initialSongs = initialCatalog.songs

        libraryStore = LibraryStore(
            songs: initialSongs,
            featuredSongIDs: initialCatalog.featuredSongIDs,
            favoriteSongIDs: initialCatalog.favoriteSongIDs
        )
        playlistStore = PlaylistStore(playlists: initialCatalog.playlists)

        queueStore = QueueStore(
            queueSongs: initialSongs,
            queueIndex: 0,
            isShuffleOn: initialShuffle,
            repeatMode: initialRepeatMode
        )
        playbackController = PlaybackController()
        playbackProgress = playbackController.progress
        snapshotStore = PlaybackSnapshotStore(settingsStore: settingsStore)

        songs = libraryStore.songs
        featuredSongIDs = libraryStore.featuredSongIDs
        favoriteSongIDs = libraryStore.favoriteSongIDs
        playlists = playlistStore.playlists
        deviceTracks = deviceMediaStore.deviceTracks

        queueSongs = queueStore.queueSongs
        queueIndex = queueStore.queueIndex
        currentSongID = queueStore.currentSong?.id

        isMiniPlayerHidden = playerUIStore.isMiniPlayerHidden
        playerSheetSong = playerUIStore.playerSheetSong
        musicStorageFolderPath = deviceMediaStore.musicStorageFolderPath
        musicStorageFolderStatus = deviceMediaStore.musicStorageFolderStatus
        user = userInfoStore.user

        ensureMusicStorageFolderExists()
        bindSettingsStore()
        bindQueueStore()
        bindPlaybackController()
        bindSleepTimerService()
        bindProgressSnapshotPersistence()
    }

    func handleSceneDidBecomeActive() {
        if !didPerformInitialActivationWork {
            didPerformInitialActivationWork = true
            restorePlaybackSnapshotIfAvailable()
        }
        refreshDeviceTracks()
    }

    var featuredSongs: [Song] {
        libraryUseCases.featuredSongs(songs: songs, featuredSongIDs: featuredSongIDs)
    }

    var favoriteSongs: [Song] {
        libraryUseCases.favoriteSongs(songs: songs, favoriteSongIDs: favoriteSongIDs)
    }

    var currentSong: Song? {
        if let song = playerCoordinator.currentSong {
            return song
        }
        guard let currentSongID else { return nil }
        return songs.first(where: { $0.id == currentSongID })
    }

    var shouldShowMiniPlayer: Bool {
        hasPlaybackSession && !isMiniPlayerHidden && currentSong != nil
    }

    var sleepTimerText: String? {
        guard let remaining = sleepTimerRemaining, remaining > 0 else { return nil }
        let total = Int(remaining)
        let minute = total / 60
        let second = total % 60
        let time = String(format: "%d:%02d", minute, second)
        return String(format: localized("player.sleep.remaining"), time)
    }

    func localized(_ key: String) -> String {
        Localizer.string(key, language: language)
    }

    func songsCountText(_ count: Int) -> String {
        String(format: localized("songs.count"), count)
    }

    func localizedSongTitle(_ song: Song) -> String {
        song.localizedTitle(for: language)
    }

    func localizedPlaylistName(_ playlist: Playlist) -> String {
        playlist.localizedName(for: language)
    }

    func repeatModeTitle() -> String {
        localized(repeatMode.localizationKey)
    }

    func song(for id: UUID) -> Song? {
        libraryUseCases.song(for: id, in: songs)
    }

    func isCurrentSong(_ song: Song) -> Bool {
        isSameTrack(currentSong, song)
    }

    func play(song: Song) {
        playerCoordinator.play(song: song, playbackSpeed: playbackSpeed)
        syncPlayerStateFromCoordinator()
    }

    func play(song: Song, in queue: [Song]) {
        playerCoordinator.play(song: song, in: queue, playbackSpeed: playbackSpeed)
        syncPlayerStateFromCoordinator()
    }

    func playFromQueue(index: Int) {
        playerCoordinator.playFromQueue(index: index, playbackSpeed: playbackSpeed)
        syncPlayerStateFromCoordinator()
    }

    func togglePlayPause() {
        playerCoordinator.togglePlayPause(playbackSpeed: playbackSpeed)
        syncPlayerStateFromCoordinator()
    }

    func hideMiniPlayer() {
        stopPlaybackAndHideMiniPlayer()
    }

    func stopAndResetPlayback() {
        cancelSleepTimer()
        playerCoordinator.stopAndResetPlayback(fallbackDuration: currentSong?.duration ?? 1)
        syncPlayerStateFromCoordinator()
    }

    func presentPlayer(for song: Song) {
        playerSheetSong = song
    }

    func stopPlaybackAndHideMiniPlayer() {
        cancelSleepTimer()
        playerCoordinator.stopPlaybackAndHideMiniPlayer()
        syncPlayerStateFromCoordinator()
    }

    func setPlaybackSpeed(_ speed: Double) {
        playbackSpeed = speed
        playerCoordinator.updatePlaybackSpeed(speed)
    }

    func setSleepTimer(minutes: Double?) {
        guard let minutes, minutes > 0 else {
            cancelSleepTimer()
            return
        }

        sleepTimerService.start(minutes: minutes) { [weak self] in
            guard let self else { return }
            self.playbackController.pause()
        }
    }

    func cancelSleepTimer() {
        sleepTimerService.cancel()
    }

    func pauseLiveProgressUpdates(seconds: Double) {
        playbackController.pauseLiveProgressUpdates(seconds: seconds)
    }

    func resumeLiveProgressUpdates() {
        playbackController.resumeLiveProgressUpdates()
    }

    func seek(to normalizedProgress: Double) {
        playerCoordinator.seek(
            to: normalizedProgress,
            fallbackDuration: currentSong?.duration ?? 1
        )
        syncPlayerStateFromCoordinator()
    }

    func displayDuration(for song: Song) -> Double {
        if isSameTrack(song, currentSong), playbackProgress.duration > 0 {
            return playbackProgress.duration
        }
        return song.duration
    }

    func toggleFavorite(for song: Song) {
        favoriteSongIDs = libraryUseCases.toggleFavorite(
            songID: song.id,
            currentFavorites: favoriteSongIDs
        )
    }

    func nextSong() {
        playerCoordinator.nextSong(playbackSpeed: playbackSpeed, autoTriggered: false)
        syncPlayerStateFromCoordinator()
    }

    func previousSong() {
        playerCoordinator.previousSong(playbackSpeed: playbackSpeed)
        syncPlayerStateFromCoordinator()
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off:
            repeatMode = .all
        case .all:
            repeatMode = .one
        case .one:
            repeatMode = .off
        }
    }

    func createPlaylist(name: String) {
        playlists = playlistUseCases.createPlaylist(name: name, in: playlists)
    }

    func deletePlaylist(at offsets: IndexSet) {
        playlists = playlistUseCases.deletePlaylists(at: offsets, in: playlists)
    }

    func addSong(_ song: Song, to playlistID: UUID) {
        playlists = playlistUseCases.addSong(song, to: playlistID, in: playlists)
    }

    func songs(in playlist: Playlist) -> [Song] {
        playlistUseCases.songs(in: playlist, allSongs: songs)
    }

    func refreshDeviceTracks() {
        let ensureResult = deviceMediaService.ensureStorageFolderExists(localized: localized)
        musicStorageFolderPath = ensureResult.path
        musicStorageFolderStatus = ensureResult.status

        guard let musicFolderURL = ensureResult.folderURL else {
            deviceTracks = []
            return
        }

        ioQueue.async { [weak self] in
            guard let self else { return }
            let tracks = self.deviceMediaService.loadDeviceTracks(in: musicFolderURL)
            Task { @MainActor [weak self] in
                self?.deviceTracks = tracks
            }
        }
    }

    func importAudioFiles(from urls: [URL], completion: @escaping (ImportResult) -> Void) {
        let ensureResult = deviceMediaService.ensureStorageFolderExists(localized: localized)
        musicStorageFolderPath = ensureResult.path
        musicStorageFolderStatus = ensureResult.status

        guard let destinationFolder = ensureResult.folderURL else {
            completion(ImportResult(importedCount: 0, skippedCount: 0, failedCount: urls.count))
            return
        }

        ioQueue.async { [weak self] in
            guard let self else { return }

            let counts = self.deviceMediaService.importAudioFiles(
                from: urls,
                destinationFolder: destinationFolder
            )

            let result = ImportResult(
                importedCount: counts.imported,
                skippedCount: counts.skipped,
                failedCount: counts.failed
            )
            let tracks = self.deviceMediaService.loadDeviceTracks(in: destinationFolder)

            Task { @MainActor [weak self] in
                self?.deviceTracks = tracks
                completion(result)
            }
        }
    }

    func importSummaryText(_ result: ImportResult) -> String {
        String(
            format: localized("home.device.music.import.result"),
            result.importedCount,
            result.skippedCount,
            result.failedCount
        )
    }

    func songForDeviceTrack(_ track: LocalAudioTrack) -> Song {
        Song(
            id: stableSongID(forLocalPath: track.url.path),
            titleEN: track.displayName,
            titleVI: track.displayName,
            artist: localized("device.artist"),
            album: localized("home.device.music"),
            coverSymbol: "iphone.gen3",
            audioFileName: track.fileName,
            localFilePath: track.url.path,
            duration: track.duration,
            accent: .green
        )
    }

    private func suggestedQueue(for song: Song) -> [Song] {
        libraryUseCases.suggestedQueue(
            for: song,
            songs: songs,
            deviceTracks: deviceTracks,
            trackToSong: songForDeviceTrack
        )
    }

    func musicStorageURL() -> URL? {
        deviceMediaService.storageFolderURL()
    }

    private func ensureMusicStorageFolderExists() {
        let result = deviceMediaService.ensureStorageFolderExists(localized: localized)
        musicStorageFolderPath = result.path
        musicStorageFolderStatus = result.status
    }

    private func stableSongID(forLocalPath path: String) -> UUID {
        let digest = SHA256.hash(data: Data(path.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let uuid = uuid_t(bytes[0], bytes[1], bytes[2], bytes[3],
                          bytes[4], bytes[5], bytes[6], bytes[7],
                          bytes[8], bytes[9], bytes[10], bytes[11],
                          bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: uuid)
    }

    private func bindSettingsStore() {
        settingsStore.$shuffleEnabled
            .removeDuplicates()
            .sink { [weak self] shuffleEnabled in
                guard let self, self.isShuffleOn != shuffleEnabled else { return }
                self.isShuffleOn = shuffleEnabled
            }
            .store(in: &cancellables)

        settingsStore.$repeatMode
            .removeDuplicates()
            .sink { [weak self] repeatMode in
                guard let self, self.repeatMode != repeatMode else { return }
                self.repeatMode = repeatMode
            }
            .store(in: &cancellables)
    }

    private func bindQueueStore() {
        queueStore.$queueSongs
            .sink { [weak self] value in
                self?.queueSongs = value
            }
            .store(in: &cancellables)

        queueStore.$queueIndex
            .sink { [weak self] value in
                self?.queueIndex = value
            }
            .store(in: &cancellables)
    }

    private func bindPlaybackController() {
        playbackController.$isPlaying
            .removeDuplicates()
            .sink { [weak self] value in
                self?.isPlaying = value
            }
            .store(in: &cancellables)

        playbackController.onDidFinish = { [weak self] in
            guard let self else { return }
            self.playerCoordinator.handleSongDidFinish(
                repeatMode: self.repeatMode,
                playbackSpeed: self.playbackSpeed
            )
            self.syncPlayerStateFromCoordinator()
        }
    }

    private func bindSleepTimerService() {
        sleepTimerService.$remaining
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.sleepTimerRemaining = value
            }
            .store(in: &cancellables)
    }

    private func bindProgressSnapshotPersistence() {
        playbackProgress.$currentTime
            .sink { [weak self] time in
                guard let self else { return }
                let wholeSecond = Int(time.rounded(.down))
                self.playerCoordinator.handleProgressTickForSnapshotPersistence(
                    wholeSecond: wholeSecond,
                    currentTime: time
                )
            }
            .store(in: &cancellables)
    }

    func savePlaybackSnapshotNow() {
        playerCoordinator.saveSnapshotNow()
    }

    private func restorePlaybackSnapshotIfAvailable() {
        playerCoordinator.restorePlaybackSnapshotIfAvailable(
            resolveSong: resolveSong(for:),
            playbackSpeed: playbackSpeed
        )
        syncPlayerStateFromCoordinator()
    }

    private func resolveSong(for snapshot: PlaybackSnapshot) -> Song? {
        if let localPath = snapshot.localFilePath {
            if let track = deviceTracks.first(where: { $0.url.path == localPath }) {
                return songForDeviceTrack(track)
            }

            if FileManager.default.fileExists(atPath: localPath) {
                let localURL = URL(fileURLWithPath: localPath)
                let duration = AVURLAsset(url: localURL).duration.seconds
                let track = LocalAudioTrack(
                    id: localURL,
                    url: localURL,
                    fileName: localURL.lastPathComponent,
                    displayName: localURL.deletingPathExtension().lastPathComponent,
                    duration: duration.isFinite && duration > 0 ? duration : 180
                )
                return songForDeviceTrack(track)
            }
        }

        if let track = deviceTracks.first(where: { $0.fileName == snapshot.audioFileName }) {
            return songForDeviceTrack(track)
        }

        if let song = songs.first(where: { $0.audioFileName == snapshot.audioFileName && $0.titleEN == snapshot.titleEN }) {
            return song
        }

        return songs.first(where: { $0.audioFileName == snapshot.audioFileName })
    }

    private func syncPlayerStateFromCoordinator() {
        currentSongID = playerCoordinator.currentSongID
        hasPlaybackSession = playerCoordinator.hasPlaybackSession
    }

    private func isSameTrack(_ lhs: Song?, _ rhs: Song?) -> Bool {
        guard let lhs, let rhs else { return false }

        if let lhsPath = lhs.localFilePath, let rhsPath = rhs.localFilePath {
            return lhsPath == rhsPath
        }

        if lhs.id == rhs.id {
            return true
        }

        return lhs.audioFileName == rhs.audioFileName && lhs.titleEN == rhs.titleEN
    }
}
